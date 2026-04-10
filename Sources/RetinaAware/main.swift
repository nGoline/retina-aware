import Foundation
import AppKit
import CoreGraphics
import Carbon

// --- Private API Definitions ---
typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32

enum ScreenSide {
    case left, right, top, bottom, none
}

class BrightnessManager {
    private var getBrightness: GetBrightnessFunc?
    private var setBrightness: SetBrightnessFunc?
    private var frameworkHandle: UnsafeMutableRawPointer?

    private var builtInDisplayID: CGDirectDisplayID?
    private var externalDisplayID: CGDirectDisplayID?
    private var transitionSide: ScreenSide = .left
    
    // Settings (Programmable)
    var approachThreshold: CGFloat = 150.0 // Pixels from border
    var dimBrightness: Float = 0.01 // Just above zero
    var activeBrightness: Float = 0.5 // Default active brightness
    var dimDelay: TimeInterval = 5.0 // Seconds before dimming
    
    // State
    private var isMouseOnRetina = false
    private var lastRetinaExitTime: Date?
    private var wakeTimeMultiplier: Double = 1.0
    private var timer: Timer?
    private var dimTimer: Timer?
    
    init() {
        loadFramework()
        findDisplays()
        setupHotkeys()
        
        if let id = builtInDisplayID {
            var current: Float = 0
            if getBrightness?(id, &current) == 0 {
                activeBrightness = current
                print("Initial active brightness detected: \(activeBrightness)")
            }
        }
    }
    
    private func loadFramework() {
        let frameworkPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        frameworkHandle = dlopen(frameworkPath, RTLD_NOW)
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
            let deviceID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let id = deviceID else { continue }
            
            if CGDisplayIsBuiltin(id) != 0 {
                builtInDisplayID = id
                retinaFrame = screen.frame
            } else {
                externalDisplayID = id
                externalFrame = screen.frame
            }
        }
        
        // Detect side
        if let retina = retinaFrame, let external = externalFrame {
            if retina.maxX <= external.minX {
                transitionSide = .left
                print("Retina is to the LEFT of External.")
            } else if retina.minX >= external.maxX {
                transitionSide = .right
                print("Retina is to the RIGHT of External.")
            } else if retina.maxY <= external.minY {
                transitionSide = .bottom
                print("Retina is BELOW External.")
            } else if retina.minY >= external.maxY {
                transitionSide = .top
                print("Retina is ABOVE External.")
            }
        }
    }
    
    private func setupHotkeys() {
        // Register F1, F2, F3 for 1m, 5m, 10m wake (Example keys)
        // In a real app, these should be user-configurable
        registerHotkey(id: 1, keyCode: 122, modifiers: UInt32(cmdKey)) // Cmd + F1
        registerHotkey(id: 2, keyCode: 120, modifiers: UInt32(cmdKey)) // Cmd + F2
        registerHotkey(id: 3, keyCode: 99, modifiers: UInt32(cmdKey))  // Cmd + F3
    }
    
    private func registerHotkey(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(signature: 0x52415752, id: id) // "RAWR"
        
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        // Setup event handler
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, event, userData) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            
            let manager = Unmanaged<BrightnessManager>.fromOpaque(userData!).takeUnretainedValue()
            
            switch hotKeyID.id {
            case 1: manager.forceWake(duration: 60)
            case 2: manager.forceWake(duration: 300)
            case 3: manager.forceWake(duration: 600)
            default: break
            }
            
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
    
    func start() {
        print("Starting Retina Aware manager...")
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
        
        // Run loop with event handling for hotkeys
        let runLoop = RunLoop.current
        while true {
            runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
    }
    
    private func checkMousePosition() {
        let mousePos = NSEvent.mouseLocation
        let onRetina = isPointOnRetina(mousePos)
        
        if onRetina && !isMouseOnRetina {
            handleRetinaEntry()
        } else if !onRetina && isMouseOnRetina {
            handleRetinaExit()
        } else if !onRetina {
            checkApproach(mousePos)
        }
        
        isMouseOnRetina = onRetina
    }
    
    private func isPointOnRetina(_ point: NSPoint) -> Bool {
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            if id == builtInDisplayID {
                return NSPointInRect(point, screen.frame)
            }
        }
        return false
    }
    
    private func handleRetinaEntry() {
        dimTimer?.invalidate()
        dimTimer = nil
        
        if let id = builtInDisplayID {
            setBrightness?(id, activeBrightness)
        }
        
        if let lastExit = lastRetinaExitTime {
            let timeSinceExit = Date().timeIntervalSince(lastExit)
            if timeSinceExit < 10.0 {
                wakeTimeMultiplier = min(wakeTimeMultiplier * 1.5, 10.0)
                print("Returned quickly! Wake delay: \(dimDelay * wakeTimeMultiplier)s")
            } else {
                wakeTimeMultiplier = 1.0
            }
        }
    }
    
    private func handleRetinaExit() {
        lastRetinaExitTime = Date()
        let delay = dimDelay * wakeTimeMultiplier
        
        dimTimer?.invalidate()
        dimTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.dimRetina()
        }
    }
    
    private func dimRetina() {
        if let id = builtInDisplayID {
            setBrightness?(id, dimBrightness)
        }
    }
    
    private func checkApproach(_ mousePos: NSPoint) {
        guard let builtInID = builtInDisplayID else { return }
        
        var distance: CGFloat = approachThreshold + 1
        
        // Simplified boundary check based on transitionSide
        switch transitionSide {
        case .left:
            if mousePos.x >= 0 && mousePos.x < approachThreshold {
                distance = mousePos.x
            }
        case .right:
            // Needs exact screen frame info for robustness, but here's the logic
            break 
        default: break
        }
        
        if distance <= approachThreshold {
            let proximity = (approachThreshold - distance) / approachThreshold
            let targetBrightness = dimBrightness + (activeBrightness - dimBrightness) * Float(proximity)
            setBrightness?(builtInID, targetBrightness)
        }
    }
    
    func forceWake(duration: TimeInterval) {
        print("FORCE WAKE for \(duration)s triggered.")
        if let id = builtInDisplayID {
            setBrightness?(id, activeBrightness)
        }
        dimTimer?.invalidate()
        dimTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dimRetina()
        }
    }
}

let manager = BrightnessManager()
manager.start()
