import Foundation
import ApplicationServices

class KeyRemapper {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    
    private var isEnabled = true
    private var xcodeOnly = false
    private var mapping: KeyMapping
    
    private let stateQueue = DispatchQueue(label: "KeyRemapper.state.queue", qos: .userInteractive)
    private var frontmostBundleID: String?
    
    init(mapping: KeyMapping) {
        self.mapping = mapping
    }
    
    func start() {
        if tapThread != nil { return }
        
        let thread = Thread { [weak self] in
            self?.tapThreadEntry()
        }
        thread.name = "KeyRemapper.EventTap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
    }
    
    private func tapThreadEntry() {
        let runLoop = CFRunLoopGetCurrent()
        self.tapRunLoop = runLoop
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let remapper = Unmanaged<KeyRemapper>.fromOpaque(refcon).takeUnretainedValue()
                return remapper.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("イベントタップの作成に失敗しました")
            return
        }
        
        self.eventTap = eventTap
        
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        print("sktdrkanaが起動しました")
        
        CFRunLoopRun()
        
        if let source = self.runLoopSource {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        self.runLoopSource = nil
        self.eventTap = nil
        self.tapRunLoop = nil
    }
    
    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }
        
        if xcodeOnly {
            var bundleID: String?
            stateQueue.sync {
                bundleID = self.frontmostBundleID
            }
            if bundleID != "com.apple.dt.Xcode" {
                return Unmanaged.passUnretained(event)
            }
        }
        
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        if keyCode == mapping.sourceKey {
            let hasRequiredModifiers = checkModifiers(flags: flags, required: mapping.sourceModifiers)
            
            if hasRequiredModifiers {
                guard let newEvent = event.copy() else {
                    return Unmanaged.passUnretained(event)
                }
                
                var newFlags = flags
                newFlags.remove(.maskShift)
                newFlags.remove(.maskControl)
                newFlags.remove(.maskCommand)
                newFlags.remove(.maskAlternate)
                newFlags.insert(mapping.targetModifiers)
                
                newEvent.flags = newFlags
                
                if mapping.sourceKey != mapping.targetKey {
                    newEvent.setIntegerValueField(.keyboardEventKeycode, value: Int64(mapping.targetKey))
                }
                
                return Unmanaged.passRetained(newEvent)
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func checkModifiers(flags: CGEventFlags, required: CGEventFlags) -> Bool {
        if required.contains(.maskShift) && !flags.contains(.maskShift) { return false }
        if required.contains(.maskControl) && !flags.contains(.maskControl) { return false }
        if required.contains(.maskCommand) && !flags.contains(.maskCommand) { return false }
        if required.contains(.maskAlternate) && !flags.contains(.maskAlternate) { return false }
        
        if !required.contains(.maskShift) && flags.contains(.maskShift) { return false }
        if !required.contains(.maskControl) && flags.contains(.maskControl) { return false }
        if !required.contains(.maskCommand) && flags.contains(.maskCommand) { return false }
        if !required.contains(.maskAlternate) && flags.contains(.maskAlternate) { return false }
        
        return true
    }
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }
    
    func setXcodeOnly(_ enabled: Bool) {
        xcodeOnly = enabled
    }
    
    func setFrontmostBundleID(_ id: String?) {
        stateQueue.async {
            self.frontmostBundleID = id
        }
    }
    
    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let rl = tapRunLoop {
            CFRunLoopStop(rl)
        }
        tapThread = nil
    }
    
    deinit {
        stop()
    }
}
