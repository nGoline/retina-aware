import SwiftUI
import AppKit
import CoreGraphics
import Carbon
import ServiceManagement

// --- Models ---

class SettingsManager: ObservableObject {
    @AppStorage("isEnabled") var isEnabled: Bool = true
    @AppStorage("approachThreshold") var approachThreshold: Double = 150.0
    @AppStorage("dimBrightness") var dimBrightness: Double = 0.01
    @AppStorage("activeBrightness") var activeBrightness: Double = 0.5
    @AppStorage("dimDelay") var dimDelay: Double = 5.0
    @AppStorage("maxWakeMultiplier") var maxWakeMultiplier: Double = 10.0
    @AppStorage("returnWindow") var returnWindow: Double = 10.0
    @AppStorage("startAtLogin") var startAtLogin: Bool = false {
        didSet { updateLoginItem() }
    }
    
    @AppStorage("wakeDuration1") var wakeDuration1: Double = 60.0
    @AppStorage("wakeDuration2") var wakeDuration2: Double = 300.0
    @AppStorage("wakeDuration3") var wakeDuration3: Double = 600.0
    
    @AppStorage("hotkey1") var hotkey1: Int = 122 // F1
    @AppStorage("hotkey2") var hotkey2: Int = 120 // F2
    @AppStorage("hotkey3") var hotkey3: Int = 99  // F3
    
    private func updateLoginItem() {
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
    @Published var isDimmed: Bool = true // FIX: Start dimmed for the moon icon
    
    private var getBrightness: GetBrightnessFunc?
    private var setBrightness: SetBrightnessFunc?
    private var frameworkHandle: UnsafeMutableRawPointer?

    private var builtInDisplayID: CGDirectDisplayID?
    private var hotKeyRefs: [EventHotKeyRef?] = [nil, nil, nil]
    
    private var isMouseOnRetina = false
    private var lastRetinaExitTime: Date?
    private var wakeTimeMultiplier: Double = 1.0
    private var timer: Timer?
    private var dimTimer: Timer?
    private var scheduledDimFireDate: Date?
    
    var settings: SettingsManager?

    init() {
        loadFramework()
        findDisplays()
    }
    
    func setup(with settings: SettingsManager) {
        self.settings = settings
        setupHotkeys()
        
        // Ensure startup state matches isDimmed = true
        if settings.isEnabled {
            dimRetina()
        } else {
            applyBrightness(Float(settings.activeBrightness))
            self.isDimmed = false
        }
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
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
    }

    private func checkMousePosition() {
        guard let settings = settings, settings.isEnabled else { return }
        
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
        return NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }?.frame.contains(point) ?? false
    }

    private func handleRetinaEntry() {
        // Save fire date so handleRetinaExit can preserve a longer active timer
        if let timer = dimTimer, timer.isValid {
            scheduledDimFireDate = timer.fireDate
        }
        dimTimer?.invalidate()
        dimTimer = nil
        DispatchQueue.main.async { self.isDimmed = false }
        if let settings = settings {
            applyBrightness(Float(settings.activeBrightness))
        }
        
        if let lastExit = lastRetinaExitTime, let settings = settings {
            if Date().timeIntervalSince(lastExit) < settings.returnWindow {
                wakeTimeMultiplier = min(wakeTimeMultiplier * 1.5, settings.maxWakeMultiplier)
            } else {
                wakeTimeMultiplier = 1.0
            }
        }
    }

    private func handleRetinaExit() {
        lastRetinaExitTime = Date()
        guard let settings = settings else { return }
        let baseDelay = settings.dimDelay * wakeTimeMultiplier
        var delay = baseDelay

        // Case: hotkey was pressed while mouse was ON Retina (dimTimer still active)
        if let currentTimer = dimTimer, currentTimer.isValid {
            let remaining = currentTimer.fireDate.timeIntervalSinceNow
            if remaining > delay { delay = remaining }
        }

        // Case: hotkey was pressed while mouse was OFF Retina, then mouse entered (timer was saved)
        if let fireDate = scheduledDimFireDate {
            let remaining = fireDate.timeIntervalSinceNow
            if remaining > delay { delay = remaining }
            scheduledDimFireDate = nil
        }

        dimTimer?.invalidate()
        dimTimer = Timer.scheduledTimer(withTimeInterval: max(0.01, delay), repeats: false) { [weak self] _ in
            self?.dimRetina()
            self?.dimTimer = nil
        }
    }

    func dimRetina() {
        DispatchQueue.main.async { self.isDimmed = true }
        if let settings = settings {
            applyBrightness(Float(settings.dimBrightness))
        }
    }

    private func checkApproach(_ mousePos: NSPoint) {
        guard let id = builtInDisplayID,
              let settings = settings,
              let retinaScreen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }) else { return }
        
        let retinaFrame = retinaScreen.frame
        let threshold = CGFloat(settings.approachThreshold)
        
        let dx = max(retinaFrame.minX - mousePos.x, 0, mousePos.x - retinaFrame.maxX)
        let dy = max(retinaFrame.minY - mousePos.y, 0, mousePos.y - retinaFrame.maxY)
        let distance = sqrt(dx*dx + dy*dy)
        
        if distance <= threshold {
            if dimTimer == nil {
                let proximity = (threshold - distance) / threshold
                let target = settings.dimBrightness + (settings.activeBrightness - settings.dimBrightness) * Double(proximity)
                applyBrightness(Float(target))
                DispatchQueue.main.async { self.isDimmed = false }
            }
        } else {
            if dimTimer == nil && !isDimmed {
                dimRetina()
            }
        }
    }

    func applyBrightness(_ value: Float) {
        if let id = builtInDisplayID { _ = setBrightness?(id, value) }
    }

    func setupHotkeys() {
        clearHotkeys()
        guard let settings = settings else { return }
        registerHotkey(id: 1, keyCode: UInt32(settings.hotkey1))
        registerHotkey(id: 2, keyCode: UInt32(settings.hotkey2))
        registerHotkey(id: 3, keyCode: UInt32(settings.hotkey3))
    }
    
    private func clearHotkeys() {
        for i in 0..<hotKeyRefs.count {
            if let ref = hotKeyRefs[i] {
                UnregisterEventHotKey(ref)
                hotKeyRefs[i] = nil
            }
        }
    }

    private func registerHotkey(id: UInt32, keyCode: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x52415752, id: id)
        RegisterEventHotKey(keyCode, UInt32(cmdKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        hotKeyRefs[Int(id-1)] = hotKeyRef
        
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            var hID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hID)
            let mgr = Unmanaged<BrightnessManager>.fromOpaque(userData!).takeUnretainedValue()
            
            guard let settings = mgr.settings, settings.isEnabled else { return noErr }
            
            switch hID.id {
                case 1: mgr.forceWake(duration: settings.wakeDuration1)
                case 2: mgr.forceWake(duration: settings.wakeDuration2)
                case 3: mgr.forceWake(duration: settings.wakeDuration3)
                default: break
            }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    func forceWake(duration: TimeInterval) {
        DispatchQueue.main.async { self.isDimmed = false }
        if let settings = settings {
            applyBrightness(Float(settings.activeBrightness))
        }
        dimTimer?.invalidate()
        dimTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dimRetina()
            self?.dimTimer = nil
        }
    }
}

// --- Views ---

struct LabelWithTooltip: View {
    let text: String
    let tooltip: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .help(tooltip)
    }
}

struct HotkeyRecorder: View {
    @Binding var keyCode: Int
    @State private var isRecording = false
    let label: String
    let tooltip: String
    
    var body: some View {
        HStack {
            LabelWithTooltip(text: label, tooltip: tooltip)
                .font(.subheadline)
            Spacer()
            Button(action: { isRecording = true }) {
                Text(isRecording ? "• • •" : keyName(for: keyCode))
                    .frame(width: 80)
            }
            .buttonStyle(.bordered)
            .background(KeyEventView(isRecording: $isRecording, keyCode: $keyCode))
        }
    }
    
    private func keyName(for code: Int) -> String {
        let mapping: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        return mapping[code] ?? "Key \(code)"
    }
}

struct KeyEventView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: Int
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if isRecording {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                self.keyCode = Int(event.keyCode)
                self.isRecording = false
                return nil
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            Divider()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var manager: BrightnessManager
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("RetinaAware").font(.system(size: 18, weight: .bold))
                Spacer()
                Toggle("", isOn: $settings.isEnabled)
                    .toggleStyle(.switch)
                    .help("Enable or disable RetinaAware entirely.")
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
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        SectionHeader(title: "DISPLAY CONFIGURATION")
                        
                        Toggle("Start at Login", isOn: $settings.startAtLogin)
                            .help("Automatically launch RetinaAware when you log into your Mac.")
                    }
                    
                    Group {
                        SectionHeader(title: "BRIGHTNESS LEVELS")
                        VStack(alignment: .leading, spacing: 8) {
                            LabelWithTooltip(text: "Active Brightness: \(Int(settings.activeBrightness * 100))%", tooltip: "The brightness level used when you are actively using the Retina display.")
                            Slider(value: $settings.activeBrightness, in: 0...1)
                            
                            LabelWithTooltip(text: "Dimmed Brightness: \(Int(settings.dimBrightness * 100))%", tooltip: "The low brightness level used to protect the screen when the mouse is on another monitor.")
                            Slider(value: $settings.dimBrightness, in: 0...0.2)
                            
                            Button("Test Levels (2s cycle)") {
                                manager.applyBrightness(Float(settings.activeBrightness))
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    if settings.isEnabled {
                                        manager.applyBrightness(Float(settings.dimBrightness))
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .help("Instantly cycles between Active and Dimmed brightness to verify your settings.")
                        }
                    }
                    
                    Group {
                        SectionHeader(title: "BEHAVIOR")
                        VStack(spacing: 12) {
                            HStack {
                                LabelWithTooltip(text: "Approach Trigger", tooltip: "How far the mouse needs to be from the border to start waking up the display.")
                                Spacer()
                                Stepper("\(Int(settings.approachThreshold))px", value: $settings.approachThreshold, in: 50...500, step: 10)
                            }
                            
                            HStack {
                                LabelWithTooltip(text: "Base Dim Delay", tooltip: "The initial grace period (seconds) before the screen dims after the mouse leaves.")
                                Spacer()
                                Stepper("\(Int(settings.dimDelay))s", value: $settings.dimDelay, in: 1...60)
                            }
                            
                            HStack {
                                LabelWithTooltip(text: "Max Wake Multiplier", tooltip: "The maximum multiplier applied to the dim delay if you keep returning to the screen frequently.")
                                Spacer()
                                Stepper("\(Int(settings.maxWakeMultiplier))x", value: $settings.maxWakeMultiplier, in: 1...20)
                            }
                            
                            HStack {
                                LabelWithTooltip(text: "Return Window", tooltip: "The time window (seconds) within which returning to the screen triggers the wake extension.")
                                Spacer()
                                Stepper("\(Int(settings.returnWindow))s", value: $settings.returnWindow, in: 5...60)
                            }
                        }
                    }
                    
                    Group {
                        SectionHeader(title: "HOTKEYS (CMD + RECORDED KEY)")
                        VStack(spacing: 10) {
                            HStack {
                                HotkeyRecorder(keyCode: $settings.hotkey1, label: "Wake 1", tooltip: "Override duration for Cmd+RecordedKey manual wake trigger.")
                                Spacer()
                                Stepper("\(Int(settings.wakeDuration1 / 60))m", value: $settings.wakeDuration1, in: 60...3600, step: 60)
                            }
                            HStack {
                                HotkeyRecorder(keyCode: $settings.hotkey2, label: "Wake 2", tooltip: "Override duration for Cmd+RecordedKey manual wake trigger.")
                                Spacer()
                                Stepper("\(Int(settings.wakeDuration2 / 60))m", value: $settings.wakeDuration2, in: 60...3600, step: 60)
                            }
                            HStack {
                                HotkeyRecorder(keyCode: $settings.hotkey3, label: "Wake 3", tooltip: "Override duration for Cmd+RecordedKey manual wake trigger.")
                                Spacer()
                                Stepper("\(Int(settings.wakeDuration3 / 60))m", value: $settings.wakeDuration3, in: 60...3600, step: 60)
                            }
                        }
                        .onChange(of: settings.hotkey1) { _ in manager.setupHotkeys() }
                        .onChange(of: settings.hotkey2) { _ in manager.setupHotkeys() }
                        .onChange(of: settings.hotkey3) { _ in manager.setupHotkeys() }
                    }
                }
                .padding()
            }
            .onAppear {
                if manager.settings == nil {
                    manager.setup(with: settings)
                    manager.start()
                }
            }
            
            VStack(spacing: 4) {
                Divider()
                HStack {
                    Text("v1.2.3 • made with ❤️ by nGoline in 🇧🇷")
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
        .frame(width: 380, height: 650)
    }
}

@main
struct RetinaAwareApp: App {
    @StateObject private var settings = SettingsManager()
    @StateObject private var manager = BrightnessManager()
    
    var body: some Scene {
        MenuBarExtra {
            SettingsView(settings: settings, manager: manager)
        } label: {
            IconView(settings: settings, manager: manager)
        }
        .menuBarExtraStyle(.window)
    }
}

struct IconView: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var manager: BrightnessManager
    
    var body: some View {
        if !settings.isEnabled {
            Image(systemName: "cloud.sun.fill")
                .foregroundColor(.secondary)
        } else {
            if manager.isDimmed {
                Image(systemName: "moon.fill")
                    .foregroundColor(.indigo)
            } else {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(.orange)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
