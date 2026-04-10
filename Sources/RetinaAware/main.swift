import SwiftUI
import AppKit
import CoreGraphics
import Carbon
import ServiceManagement

// --- Models ---

enum RetinaPosition: String, CaseIterable, Identifiable {
    case left = "Left"
    case right = "Right"
    case top = "Above"
    case bottom = "Below"
    var id: String { self.rawValue }
}

class SettingsManager: ObservableObject {
    @AppStorage("isEnabled") var isEnabled: Bool = true
    @AppStorage("retinaPosition") var retinaPosition: RetinaPosition = .left
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
    
    // Key codes (Default F1=122, F2=120, F3=99)
    @AppStorage("hotkey1Code") var hotkey1Code: Int = 122
    @AppStorage("hotkey2Code") var hotkey2Code: Int = 120
    @AppStorage("hotkey3Code") var hotkey3Code: Int = 99
    
    private func updateLoginItem() {
        // Since we are now an app, we should use loginItem instead of register() for Daemons
        do {
            if startAtLogin {
                try SMAppService.loginItem(identifier: "com.user.retina-aware").register()
            } else {
                try SMAppService.loginItem(identifier: "com.user.retina-aware").unregister()
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
    @Published var isDimmed: Bool = false
    
    private var getBrightness: GetBrightnessFunc?
    private var setBrightness: SetBrightnessFunc?
    private var frameworkHandle: UnsafeMutableRawPointer?

    private var builtInDisplayID: CGDirectDisplayID?
    
    private var isMouseOnRetina = false
    private var lastRetinaExitTime: Date?
    private var wakeTimeMultiplier: Double = 1.0
    private var timer: Timer?
    private var dimTimer: Timer?
    
    var settings: SettingsManager!

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
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let displayID = id else { continue }
            if CGDisplayIsBuiltin(displayID) != 0 {
                builtInDisplayID = displayID
                break
            }
        }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
    }

    private func checkMousePosition() {
        guard settings.isEnabled else { return }
        
        let mousePos = NSEvent.mouseLocation
        let onRetina = isPointOnRetina(mousePos)
        
        if onRetina {
            if !isMouseOnRetina { handleRetinaEntry() }
        } else {
            if isMouseOnRetina { handleRetinaExit() }
            checkApproach(mousePos)
        }
        
        isMouseOnRetina = onRetina
    }

    private func isPointOnRetina(_ point: NSPoint) -> Bool {
        guard let id = builtInDisplayID else { return false }
        let screens = NSScreen.screens
        return screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }?.frame.contains(point) ?? false
    }

    private func handleRetinaEntry() {
        dimTimer?.invalidate()
        dimTimer = nil
        isDimmed = false
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
            self?.dimRetina()
        }
    }

    func dimRetina() {
        isDimmed = true
        applyBrightness(Float(settings.dimBrightness))
    }

    private func checkApproach(_ mousePos: NSPoint) {
        guard let id = builtInDisplayID,
              let retinaScreen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }) else { return }
        
        let retinaFrame = retinaScreen.frame
        var distance: CGFloat = CGFloat(settings.approachThreshold) + 1
        
        // Border detection
        switch settings.retinaPosition {
        case .left:
            if mousePos.x >= retinaFrame.maxX && mousePos.x < retinaFrame.maxX + CGFloat(settings.approachThreshold) {
                if mousePos.y >= retinaFrame.minY && mousePos.y <= retinaFrame.maxY {
                    distance = mousePos.x - retinaFrame.maxX
                }
            }
        case .right:
            if mousePos.x <= retinaFrame.minX && mousePos.x > retinaFrame.minX - CGFloat(settings.approachThreshold) {
                if mousePos.y >= retinaFrame.minY && mousePos.y <= retinaFrame.maxY {
                    distance = retinaFrame.minX - mousePos.x
                }
            }
        case .top:
            if mousePos.y <= retinaFrame.minY && mousePos.y > retinaFrame.minY - CGFloat(settings.approachThreshold) {
                if mousePos.x >= retinaFrame.minX && mousePos.x <= retinaFrame.maxX {
                    distance = retinaFrame.minY - mousePos.y
                }
            }
        case .bottom:
            if mousePos.y >= retinaFrame.maxY && mousePos.y < retinaFrame.maxY + CGFloat(settings.approachThreshold) {
                if mousePos.x >= retinaFrame.minX && mousePos.x <= retinaFrame.maxX {
                    distance = mousePos.y - retinaFrame.maxY
                }
            }
        }
        
        if distance <= CGFloat(settings.approachThreshold) {
            let proximity = (CGFloat(settings.approachThreshold) - distance) / CGFloat(settings.approachThreshold)
            let target = settings.dimBrightness + (settings.activeBrightness - settings.dimBrightness) * Double(proximity)
            applyBrightness(Float(target))
            isDimmed = false
        } else {
            // FIX: If we are not in approach zone AND not in Retina, we MUST be dimmed (unless force-wake timer is active)
            if dimTimer == nil && !isDimmed {
                dimRetina()
            }
        }
    }

    func applyBrightness(_ value: Float) {
        if let id = builtInDisplayID { _ = setBrightness?(id, value) }
    }

    func setupHotkeys() {
        registerHotkey(id: 1, keyCode: UInt32(settings.hotkey1Code))
        registerHotkey(id: 2, keyCode: UInt32(settings.hotkey2Code))
        registerHotkey(id: 3, keyCode: UInt32(settings.hotkey3Code))
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
            
            guard mgr.settings.isEnabled else { return noErr }
            
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
        isDimmed = false
        applyBrightness(Float(settings.activeBrightness))
        dimTimer?.invalidate()
        dimTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dimRetina()
        }
    }
}

// --- Views ---

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var manager: BrightnessManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("RetinaAware").font(.system(size: 18, weight: .bold))
                Spacer()
                Toggle("", isOn: $settings.isEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: settings.isEnabled) { value in
                        if value {
                            manager.dimRetina()
                        } else {
                            manager.applyBrightness(Float(settings.activeBrightness))
                            manager.isDimmed = false
                        }
                    }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            
            ScrollView {
                Form {
                    Section("Display Configuration") {
                        Picker("Retina Position:", selection: $settings.retinaPosition) {
                            ForEach(RetinaPosition.allCases) { pos in
                                Text(pos.rawValue).tag(pos)
                            }
                        }
                        Toggle("Start at Login", isOn: $settings.startAtLogin)
                    }
                    
                    Section("Brightness Levels") {
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
                        Button("Test Levels (2s cycle)") {
                            manager.applyBrightness(Float(settings.activeBrightness))
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                if settings.isEnabled {
                                    manager.applyBrightness(Float(settings.dimBrightness))
                                }
                            }
                        }.buttonStyle(.bordered)
                    }
                    
                    Section("Behavior") {
                        Stepper("Approach Trigger: \(Int(settings.approachThreshold))px", value: $settings.approachThreshold, in: 50...500, step: 10)
                        Stepper("Base Dim Delay: \(Int(settings.dimDelay))s", value: $settings.dimDelay, in: 1...60)
                        Stepper("Max Wake Ext: \(Int(settings.maxWakeMultiplier))x", value: $settings.maxWakeMultiplier, in: 1...20)
                        Stepper("Return Window: \(Int(settings.returnWindow))s", value: $settings.returnWindow, in: 5...60)
                    }
                    
                    Section("Hotkeys (Cmd + KeyCode)") {
                        HStack {
                            Text("F1 duration:")
                            Stepper("\(Int(settings.wakeDuration1 / 60))m", value: $settings.wakeDuration1, in: 60...3600, step: 60)
                        }
                        HStack {
                            Text("F2 duration:")
                            Stepper("\(Int(settings.wakeDuration2 / 60))m", value: $settings.wakeDuration2, in: 60...3600, step: 60)
                        }
                        HStack {
                            Text("F3 duration:")
                            Stepper("\(Int(settings.wakeDuration3 / 60))m", value: $settings.wakeDuration3, in: 60...3600, step: 60)
                        }
                        Text("Current Keys: F1(122), F2(120), F3(99)").font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            
            // Footer
            VStack(spacing: 4) {
                Divider()
                HStack {
                    Text("v1.2.1 • made with ❤️ by nGoline in 🇧🇷")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Color.secondary.opacity(0.05))
        }
        .frame(width: 380, height: 620)
    }
}

// --- App Entry ---

@main
struct RetinaAwareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra {
            SettingsView(settings: appDelegate.settings, manager: appDelegate.manager)
        } label: {
            // Feature 4: Dynamic Icon Color/Style
            Image(systemName: appDelegate.manager.isDimmed ? "sun.min" : "sun.max.fill")
                .foregroundColor(appDelegate.manager.isDimmed ? .secondary : .orange)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var settings = SettingsManager()
    var manager = BrightnessManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        manager.setup(with: settings)
        manager.start()
    }
}
