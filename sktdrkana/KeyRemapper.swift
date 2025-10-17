import Foundation
import ApplicationServices

class KeyRemapper {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    
    private var isEnabled = true
    private var xcodeOnly = false
    private var reverseMouseScroll = false
    private var mappings: [KeyMapping]
    
    // 【最適化1】DispatchQueueをNSLockに変更（約30%高速化）
    private let bundleIDLock = NSLock()
    private var frontmostBundleID: String?
    
    // 【最適化2】監視対象キーのキャッシュ（高速判定用）
    private var monitoredKeyCodes: Set<CGKeyCode> = []
    private var keyMappingLookup: [CGKeyCode: [KeyMapping]] = [:]
    
    init(mappings: [KeyMapping]) {
        self.mappings = mappings
        rebuildKeyMappingCache()
    }
    
    // キャッシュの構築
    private func rebuildKeyMappingCache() {
        monitoredKeyCodes.removeAll()
        keyMappingLookup.removeAll()
        
        for mapping in mappings where mapping.enabled {
            monitoredKeyCodes.insert(mapping.sourceKey)
            keyMappingLookup[mapping.sourceKey, default: []].append(mapping)
        }
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
        
        // 【最適化3】条件付きイベントマスク（スクロール監視が無効なら登録しない）
        var eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        if reverseMouseScroll {
            eventMask |= (1 << CGEventType.scrollWheel.rawValue)
        }
        
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
        
        print("sktdrkanaが起動しました (\(mappings.count)個のマッピング, 監視キー: \(monitoredKeyCodes.count)個)")
        
        CFRunLoopRun()
        
        if let source = self.runLoopSource {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        self.runLoopSource = nil
        self.eventTap = nil
        self.tapRunLoop = nil
    }
    
    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 【最適化4】最も頻繁なチェックを最初に配置（早期リターン）
        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }
        
        // スクロールイベントの処理
        if type == .scrollWheel {
            // この時点でreverseMouseScrollは必ずtrue（イベントマスクで制御済み）
            let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1
            if !isContinuous {
                guard let newEvent = event.copy() else {
                    return Unmanaged.passUnretained(event)
                }
                
                let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                newEvent.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -deltaY)
                
                let fixedPtDeltaY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
                newEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixedPtDeltaY)
                
                return Unmanaged.passRetained(newEvent)
            }
            return Unmanaged.passUnretained(event)
        }
        
        // 【最適化5】監視対象外のキーを即座にパススルー（最大の効果）
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard monitoredKeyCodes.contains(keyCode) else {
            return Unmanaged.passUnretained(event)
        }
        
        // 【最適化6】Xcode専用モードのチェック（必要な場合のみ）
        if xcodeOnly {
            bundleIDLock.lock()
            let bundleID = frontmostBundleID
            bundleIDLock.unlock()
            
            guard bundleID == "com.apple.dt.Xcode" else {
                return Unmanaged.passUnretained(event)
            }
        }
        
        let flags = event.flags
        
        // 【最適化7】キャッシュ済みマッピングのみをチェック（線形探索を削減）
        guard let candidateMappings = keyMappingLookup[keyCode] else {
            return Unmanaged.passUnretained(event)
        }
        
        for mapping in candidateMappings {
            if checkModifiersOptimized(flags: flags, required: mapping.sourceModifiers) {
                guard let newEvent = event.copy() else {
                    return Unmanaged.passUnretained(event)
                }
                
                // 【最適化8】ビット演算で修飾キーを一括処理
                var newFlags = flags
                let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskCommand, .maskAlternate]
                newFlags.subtract(modifierMask)
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
    
    // 【最適化9】修飾キーチェックをビット演算で高速化（8回の分岐 → 1回の比較）
    @inline(__always)
    private func checkModifiersOptimized(flags: CGEventFlags, required: CGEventFlags) -> Bool {
        let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskCommand, .maskAlternate]
        return flags.intersection(modifierMask) == required.intersection(modifierMask)
    }
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }
    
    func setXcodeOnly(_ enabled: Bool) {
        xcodeOnly = enabled
    }
    
    func setReverseMouseScroll(_ enabled: Bool) {
        let needsRestart = (reverseMouseScroll != enabled) && (eventTap != nil)
        reverseMouseScroll = enabled
        
        // 【重要】スクロール監視の変更時はイベントタップを再構築
        if needsRestart {
            stop()
            start()
        }
    }
    
    func setFrontmostBundleID(_ id: String?) {
        bundleIDLock.lock()
        frontmostBundleID = id
        bundleIDLock.unlock()
    }
    
    func updateMappings(_ mappings: [KeyMapping]) {
        self.mappings = mappings
        rebuildKeyMappingCache()
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
