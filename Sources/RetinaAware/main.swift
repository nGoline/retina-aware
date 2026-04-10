import SwiftUI
import AppKit
import CoreGraphics
import Carbon
import ServiceManagement

// --- Models ---

class SettingsManager: ObservableObject {
    @AppStorage("approachThreshold") var approachThreshold: Double = 150.0
    @AppStorage("dimBrightness") var dimBrightness: Double = 0.01
    @AppStorage("activeBrightness") var activeBrightness: Double = 0.5
    @AppStorage("dimDelay") var dimDelay: Double = 5.0
    @AppStorage("maxWakeMultiplier") var maxWakeMultiplier: Double = 10.0
    @AppStorage("returnWindow") var returnWindow: Double = 10.0
    @AppStorage("startAtLogin") var startAtLogin: Bool = false {
        didSet { updateLoginItem() }
    }
    
    // Wake durations for hotkeys
    @AppStorage("wakeDuration1") var wakeDuration1: Double = 60.0
    @AppStorage("wakeDuration2") var wakeDuration2: Double = 300.0
    @AppStorage("wakeDuration3") var wakeDuration3: Double = 600.0
    
    private func updateLoginItem() {
        do {
            if startAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }
}

// --- Brightness Logic ---

typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32

class BrightnessManager: ObservableObject {
    private var getBrightness: GetBrightnessFunc?
    private var setBrightness: SetBrightnessFunc?
    private var frameworkHandle: UnsafeMutableRawPointer?

    private var builtInDisplayID: CGDirectDisplayID?
    private var transitionSide: ScreenSide = .left
    
    private var isMouseOnRetina = false
    private var lastRetinaExitTime: Date?
    private var wakeTimeMultiplier: Double = 1.0
    private var timer: Timer?
    private var dimTimer: Timer?
    
    var settings: SettingsManager!

    enum ScreenSide { case left, right, top, bottom, none }

    init() {
        loadFramework()
        findDisplays()
    }
    
    func setup(with settings: SettingsManager) {
        self.settings = settings
        setupHotkeys()
    }

    private func loadFramework() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        frameworkHandle = dlopen(path, RTLD_NOW)
        if let handle = frameworkHandle {
            if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
                getBrightness = unsafeBitCast(sym, to: GetBrightnessFunc.self)
            }
            if let sym = dlsym(handle, "DisplayServicesSetBrightness") {
                setBrightness = unsafeBitCast(sym, to: SetBrightnessFunc.self)
            }
        }
    }

    private func findDisplays() {
        var retinaFrame: NSRect?
        var externalFrame: NSRect?
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let displayID = id else { continue }
            if CGDisplayIsBuiltin(displayID) != 0 {
                builtInDisplayID = displayID
                retinaFrame = screen.frame
            } else {
                externalFrame = screen.frame
            }
        }
        if let retina = retinaFrame, let external = externalFrame {
            if retina.maxX <= external.minX { transitionSide = .left }
            else if retina.minX >= external.maxX { transitionSide = .right }
            // etc...
        }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
    }

    private func checkMousePosition() {
        let mousePos = NSEvent.mouseLocation
        let onRetina = isPointOnRetina(mousePos)
        
        if onRetina && !isMouseOnRetina { handleRetinaEntry() }
        else if !onRetina && isMouseOnRetina { handleRetinaExit() }
        else if !onRetina { checkApproach(mousePos) }
        
        isMouseOnRetina = onRetina
    }

    private func isPointOnRetina(_ point: NSPoint) -> Bool {
        guard let id = builtInDisplayID else { return false }
        return NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }?.frame.contains(point) ?? false
    }

    private func handleRetinaEntry() {
        dimTimer?.invalidate()
        dimTimer = nil
        applyBrightness(Float(settings.activeBrightness))
        
        if let lastExit = lastRetinaExitTime {
            if Date().timeIntervalSince(lastExit) < settings.returnWindow {
                wakeTimeMultiplier = min(wakeTimeMultiplier * 1.5, settings.maxWakeMultiplier)
            } else {
                wakeTimeMultiplier = 1.0
            }
        }
    }

    private func handleRetinaExit() {
        lastRetinaExitTime = Date()
        dimTimer?.invalidate()
        dimTimer = Timer.scheduledTimer(withTimeInterval: settings.dimDelay * wakeTimeMultiplier, repeats: false) { [weak self] _ in
            self?.applyBrightness(Float(self?.settings.dimBrightness ?? 0.01))
        }
    }

    private func checkApproach(_ mousePos: NSPoint) {
        var distance: CGFloat = CGFloat(settings.approachThreshold) + 1
        if transitionSide == .left && mousePos.x >= 0 && mousePos.x < CGFloat(settings.approachThreshold) {
            distance = mousePos.x
        }
        
        if distance <= CGFloat(settings.approachThreshold) {
            let proximity = (CGFloat(settings.approachThreshold) - distance) / CGFloat(settings.approachThreshold)
            let target = settings.dimBrightness + (settings.activeBrightness - settings.dimBrightness) * Double(proximity)
            applyBrightness(Float(target))
        }
    }

    func applyBrightness(_ value: Float) {
        if let id = builtInDisplayID { _ = setBrightness?(id, value) }
    }

    private func setupHotkeys() {
        registerHotkey(id: 1, keyCode: 122) // Cmd + F1
        registerHotkey(id: 2, keyCode: 120) // Cmd + F2
        registerHotkey(id: 3, keyCode: 99)  // Cmd + F3
    }

    private func registerHotkey(id: UInt32, keyCode: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x52415752, id: id)
        RegisterEventHotKey(keyCode, UInt32(cmdKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            var hID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hID)
            let mgr = Unmanaged<BrightnessManager>.fromOpaque(userData!).takeUnretainedValue()
            switch hID.id {
                case 1: mgr.forceWake(duration: mgr.settings.wakeDuration1)
                case 2: mgr.forceWake(duration: mgr.settings.wakeDuration2)
                case 3: mgr.forceWake(duration: mgr.settings.wakeDuration3)
                default: break
            }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    func forceWake(duration: TimeInterval) {
        applyBrightness(Float(settings.activeBrightness))
        dimTimer?.invalidate()
        dimTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.applyBrightness(Float(self?.settings.dimBrightness ?? 0.01))
        }
    }
}

// --- Views ---

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var manager: BrightnessManager
    
    var body: some View {
        VStack(spacing: 20) {
            Text("RetinaAware Settings").font(.headline)
            
            Form {
                Section("General") {
                    Toggle("Start at Login", isOn: $settings.startAtLogin)
                }
                
                Section("Brightness") {
                    HStack {
                        Text("Active:")
                        Slider(value: $settings.activeBrightness, in: 0...1)
                        Text("\(Int(settings.activeBrightness * 100))%")
                    }
                    HStack {
                        Text("Dimmed:")
                        Slider(value: $settings.dimBrightness, in: 0...0.2)
                        Text("\(Int(settings.dimBrightness * 100))%")
                    }
                    Button("Test Config") {
                        manager.applyBrightness(Float(settings.activeBrightness))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            manager.applyBrightness(Float(settings.dimBrightness))
                        }
                    }.buttonStyle(.borderedProminent)
                }
                
                Section("Timing & Thresholds") {
                    Stepper("Approach Threshold: \(Int(settings.approachThreshold))px", value: $settings.approachThreshold, in: 50...500, step: 10)
                    Stepper("Base Dim Delay: \(Int(settings.dimDelay))s", value: $settings.dimDelay, in: 1...60)
                    Stepper("Max Multiplier: \(Int(settings.maxWakeMultiplier))x", value: $settings.maxWakeMultiplier, in: 1...20)
                    Stepper("Return Window: \(Int(settings.returnWindow))s", value: $settings.returnWindow, in: 5...60)
                }
                
                Section("Hotkeys (Cmd + F1/F2/F3)") {
                    Stepper("F1 Duration: \(Int(settings.wakeDuration1 / 60))m", value: $settings.wakeDuration1, in: 60...3600, step: 60)
                    Stepper("F2 Duration: \(Int(settings.wakeDuration2 / 60))m", value: $settings.wakeDuration2, in: 60...3600, step: 60)
                    Stepper("F3 Duration: \(Int(settings.wakeDuration3 / 60))m", value: $settings.wakeDuration3, in: 60...3600, step: 60)
                }
            }
            .padding()
            
            Divider()
            
            HStack {
                Text("v1.1 • made with ❤️ by nGoline in 🇧🇷")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
            }
            .padding(.horizontal)
        }
        .frame(width: 400, height: 600)
        .padding()
    }
}

// --- App Entry ---

@main
struct RetinaAwareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("RetinaAware", systemImage: "sun.max.trianglebadge.exclamationmark") {
            SettingsView(settings: appDelegate.settings, manager: appDelegate.manager)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var settings = SettingsManager()
    var manager = BrightnessManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set app to be a menu bar app (no dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        manager.setup(with: settings)
        manager.start()
    }
}
