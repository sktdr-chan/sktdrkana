import Cocoa
import ApplicationServices
import ServiceManagement

struct KeyMapping {
    var sourceModifiers: CGEventFlags  // 入力元の修飾キー（Shiftなど）
    var sourceKey: CGKeyCode           // 入力元のキー（Spaceなど）
    var targetModifiers: CGEventFlags  // 変換先の修飾キー（Controlなど）
    var targetKey: CGKeyCode           // 変換先のキー（Spaceなど）
    
    // デフォルト設定（Shift+Space → Control+Space）
    static let defaultMapping = KeyMapping(
        sourceModifiers: .maskShift,
        sourceKey: 49,  // スペースキーのキーコード
        targetModifiers: .maskControl,
        targetKey: 49
    )
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var keyRemapper: KeyRemapper?
    private var isEnabled = true
    private var currentMapping: KeyMapping = KeyMapping.defaultMapping
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var workspaceObserver: NSObjectProtocol?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load UserDefaults
        loadMapping()
        
        // メニューバーにアイコンを作成
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = false
        }
        
        // メニューを構築
        setupMenu()
        
        // キーリマッパーを起動（まずはインスタンス化のみ）
        keyRemapper = KeyRemapper(mapping: currentMapping)
        
        // フロントアプリの監視（メインスレッドで受けて、KeyRemapper にキャッシュを渡す）
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.keyRemapper?.setFrontmostBundleID(app?.bundleIdentifier)
        }
        // 初期値も渡しておく
        keyRemapper?.setFrontmostBundleID(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        
        // アクセシビリティ権限の確認
        checkAccessibilityPermission()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }
    
    private func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let alert = NSAlert()
            alert.messageText = "アクセシビリティ権限が必要です"
            alert.informativeText = "システム設定 > プライバシーとセキュリティ > アクセシビリティ から権限を付与してください"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "システム設定を開く")
            alert.addButton(withTitle: "キャンセル")
            
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            return
        }
        
        // 権限がある場合、リマッパーを開始（専用スレッドで）
        keyRemapper?.start()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // About
        let aboutItem = NSMenuItem(
            title: "About sktdrkana",
            action: #selector(openAboutWindow),
            keyEquivalent: ""
        )
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem.separator())
        
        // 有効/無効切り替え
        let toggleItem = NSMenuItem(
            title: "リマッピング: 有効",
            action: #selector(toggleRemapping),
            keyEquivalent: ""
        )
        toggleItem.state = .on
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 設定メニュー
        let settingsItem = NSMenuItem(title: "設定", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        
        // キーマッピング設定
        let keyMappingItem = NSMenuItem(
            title: "キーマッピング設定...",
            action: #selector(openKeyMappingSettings),
            keyEquivalent: ""
        )
        settingsMenu.addItem(keyMappingItem)
        
        settingsMenu.addItem(NSMenuItem.separator())
        
        // Xcode専用モード
        let xcodeOnlyItem = NSMenuItem(
            title: "Xcode専用モード",
            action: #selector(toggleXcodeOnly),
            keyEquivalent: ""
        )
        xcodeOnlyItem.state = .off
        settingsMenu.addItem(xcodeOnlyItem)
        
        // OS起動時に実行
        let launchAtLoginItem = NSMenuItem(
            title: "OS起動時に実行",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        if #available(macOS 13.0, *) {
            launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        } else {
            launchAtLoginItem.isEnabled = false
            launchAtLoginItem.toolTip = "このオプションは macOS 13 以降で利用できます"
        }
        settingsMenu.addItem(launchAtLoginItem)
        
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // ステータス表示
        let statusMenuItem = NSMenuItem(
            title: "状態: 動作中",
            action: nil,
            keyEquivalent: ""
        )
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 情報
        let infoItem = NSMenuItem(
            title: "\(modifierName(currentMapping.sourceModifiers))+\(keyName(currentMapping.sourceKey)) → \(modifierName(currentMapping.targetModifiers))+\(keyName(currentMapping.targetKey))",
            action: nil,
            keyEquivalent: ""
        )
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 終了
        menu.addItem(
            NSMenuItem(
                title: "終了",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )
        
        statusItem?.menu = menu
    }
    
    @objc private func openAboutWindow() {
        // 既に開いていれば前面に
        if let w = aboutWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About sktdrkana"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.aboutWindow = window
        
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        
        // アプリアイコン
        let iconImageView = NSImageView(frame: NSRect(x: 20, y: 220, width: 64, height: 64))
        iconImageView.image = NSApp.applicationIconImage
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(iconImageView)
        
        // アプリ名
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "sktdrkana"
        let titleLabel = NSTextField(labelWithString: appName)
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.frame = NSRect(x: 100, y: 260, width: 360, height: 24)
        contentView.addSubview(titleLabel)
        
        // バージョン
        let versionLabel = NSTextField(labelWithString: appVersionString())
        versionLabel.frame = NSRect(x: 100, y: 236, width: 360, height: 18)
        contentView.addSubview(versionLabel)
        
        // 詳細テキスト（選択可能でコピーできる）
        let textView = NSTextView(frame: NSRect(x: 20, y: 20, width: 440, height: 150))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textStorage?.setAttributedString(makeAboutAttributedString())
        contentView.addSubview(textView)
        
        // 閉じるボタン
        let closeButton = NSButton(frame: NSRect(x: 360, y: 20, width: 100, height: 30))
        closeButton.title = "閉じる"
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeAboutWindow(_:))
        contentView.addSubview(closeButton)
        
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func closeAboutWindow(_ sender: NSButton) {
        aboutWindow?.close()
    }
    
    private func appVersionString() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "Version \(version) (\(build))"
    }
    
    private func makeAboutAttributedString() -> NSAttributedString {
        let bundleID = Bundle.main.bundleIdentifier ?? "-"
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
        
        let text = """
        Bundle ID: \(bundleID)
        macOS: \(system)
        
        このアプリは、キーボードイベントをリマップするユーティリティです。
        作者sktdrがShift＋Spaceで日本語入力をOn・Offする為に作成しています。
        初期のリマップ設定: Shift+Space → Control+Space
        
        \(copyright ?? "")
        """
        
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 6
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .paragraphStyle: paragraph
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }
    
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window == settingsWindow {
                settingsWindow = nil
            } else if window == aboutWindow {
                aboutWindow = nil
            }
        }
    }
    
    @objc private func toggleRemapping(_ sender: NSMenuItem) {
        isEnabled.toggle()
        sender.state = isEnabled ? .on : .off
        sender.title = isEnabled ? "リマッピング: 有効" : "リマッピング: 無効"
        keyRemapper?.setEnabled(isEnabled)
        
        // ステータスも更新
        if let menu = statusItem?.menu {
            if let statusItem = menu.items.first(where: { $0.title.starts(with: "状態:") }) {
                statusItem.title = isEnabled ? "状態: 動作中" : "状態: 停止中"
            }
        }
    }
    
    @objc private func toggleXcodeOnly(_ sender: NSMenuItem) {
        let newState: NSControl.StateValue = sender.state == .on ? .off : .on
        sender.state = newState
        keyRemapper?.setXcodeOnly(newState == .on)
    }
    
    // OS起動時に実行（ログイン項目）トグル
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled {
                    try service.unregister()
                    sender.state = .off
                } else {
                    try service.register()
                    sender.state = .on
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "ログイン時に開くの変更に失敗しました"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                // 実際の状態に合わせてUIを戻す
                sender.state = service.status == .enabled ? .on : .off
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "未対応の macOS バージョン"
            alert.informativeText = "この機能は macOS 13 以降で利用できます。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    // 設定を保存
    private func saveMapping() {
        let defaults = UserDefaults.standard
        defaults.set(Int(currentMapping.sourceModifiers.rawValue), forKey: "sourceModifiers")
        defaults.set(Int(currentMapping.sourceKey), forKey: "sourceKey")
        defaults.set(Int(currentMapping.targetModifiers.rawValue), forKey: "targetModifiers")
        defaults.set(Int(currentMapping.targetKey), forKey: "targetKey")
    }
    
    // 設定を読み込み
    private func loadMapping() {
        let defaults = UserDefaults.standard
        
        // 保存された設定があるかチェック
        if defaults.object(forKey: "sourceKey") != nil {
            let sourceModifiers = CGEventFlags(rawValue: CGEventFlags.RawValue(defaults.integer(forKey: "sourceModifiers")))
            let sourceKey = CGKeyCode(defaults.integer(forKey: "sourceKey"))
            let targetModifiers = CGEventFlags(rawValue: CGEventFlags.RawValue(defaults.integer(forKey: "targetModifiers")))
            let targetKey = CGKeyCode(defaults.integer(forKey: "targetKey"))
            
            currentMapping = KeyMapping(
                sourceModifiers: sourceModifiers,
                sourceKey: sourceKey,
                targetModifiers: targetModifiers,
                targetKey: targetKey
            )
        }
    }
    
    @objc private func openKeyMappingSettings() {
        // ウィンドウを作成
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "キーマッピング設定"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.settingsWindow = window
        
        // コンテンツビューを作成
        let contentView = NSView(frame: window.contentView!.bounds)
        
        // タイトルラベル
        let titleLabel = NSTextField(labelWithString: "入力するキーの組み合わせ:")
        titleLabel.frame = NSRect(x: 20, y: 240, width: 360, height: 20)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        contentView.addSubview(titleLabel)
        
        // 入力元の修飾キー選択
        let sourceModifierLabel = NSTextField(labelWithString: "修飾キー:")
        sourceModifierLabel.frame = NSRect(x: 20, y: 210, width: 80, height: 20)
        contentView.addSubview(sourceModifierLabel)
        
        let sourceModifierPopup = NSPopUpButton(frame: NSRect(x: 110, y: 205, width: 150, height: 25))
        sourceModifierPopup.addItems(withTitles: ["Shift", "Control", "Command", "Option"])
        // インデックスで選択
        let sourceModIndex = modifierIndex(currentMapping.sourceModifiers)
        if sourceModIndex < sourceModifierPopup.numberOfItems {
            sourceModifierPopup.selectItem(at: sourceModIndex)
        }
        sourceModifierPopup.tag = 1
        contentView.addSubview(sourceModifierPopup)
        
        // 入力元のキー選択
        let sourceKeyLabel = NSTextField(labelWithString: "キー:")
        sourceKeyLabel.frame = NSRect(x: 20, y: 180, width: 80, height: 20)
        contentView.addSubview(sourceKeyLabel)
        
        let sourceKeyPopup = NSPopUpButton(frame: NSRect(x: 110, y: 175, width: 150, height: 25))
        sourceKeyPopup.addItems(withTitles: ["Space", "Return", "A", "B", "C"])
        // インデックスで選択
        let sourceKeyIndex = keyIndex(currentMapping.sourceKey)
        if sourceKeyIndex < sourceKeyPopup.numberOfItems {
            sourceKeyPopup.selectItem(at: sourceKeyIndex)
        }
        sourceKeyPopup.tag = 2
        contentView.addSubview(sourceKeyPopup)
        
        // 矢印
        let arrowLabel = NSTextField(labelWithString: "↓ 変換後 ↓")
        arrowLabel.frame = NSRect(x: 20, y: 145, width: 360, height: 20)
        arrowLabel.alignment = .center
        arrowLabel.font = NSFont.systemFont(ofSize: 12)
        contentView.addSubview(arrowLabel)
        
        // タイトルラベル2
        let titleLabel2 = NSTextField(labelWithString: "出力するキーの組み合わせ:")
        titleLabel2.frame = NSRect(x: 20, y: 115, width: 360, height: 20)
        titleLabel2.font = NSFont.boldSystemFont(ofSize: 13)
        contentView.addSubview(titleLabel2)
        
        // 出力先の修飾キー選択
        let targetModifierLabel = NSTextField(labelWithString: "修飾キー:")
        targetModifierLabel.frame = NSRect(x: 20, y: 85, width: 80, height: 20)
        contentView.addSubview(targetModifierLabel)
        
        let targetModifierPopup = NSPopUpButton(frame: NSRect(x: 110, y: 80, width: 150, height: 25))
        targetModifierPopup.addItems(withTitles: ["Shift", "Control", "Command", "Option"])
        // インデックスで選択
        let targetModIndex = modifierIndex(currentMapping.targetModifiers)
        if targetModIndex < targetModifierPopup.numberOfItems {
            targetModifierPopup.selectItem(at: targetModIndex)
        }
        targetModifierPopup.tag = 3
        contentView.addSubview(targetModifierPopup)
        
        // 出力先のキー選択
        let targetKeyLabel = NSTextField(labelWithString: "キー:")
        targetKeyLabel.frame = NSRect(x: 20, y: 55, width: 80, height: 20)
        contentView.addSubview(targetKeyLabel)
        
        let targetKeyPopup = NSPopUpButton(frame: NSRect(x: 110, y: 50, width: 150, height: 25))
        targetKeyPopup.addItems(withTitles: ["Space", "Return", "A", "B", "C"])
        // インデックスで選択
        let targetKeyIndex = keyIndex(currentMapping.targetKey)
        if targetKeyIndex < targetKeyPopup.numberOfItems {
            targetKeyPopup.selectItem(at: targetKeyIndex)
        }
        targetKeyPopup.tag = 4
        contentView.addSubview(targetKeyPopup)
        
        // 保存ボタン
        let saveButton = NSButton(frame: NSRect(x: 290, y: 20, width: 90, height: 30))
        saveButton.title = "保存"
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveKeyMapping(_:))
        contentView.addSubview(saveButton)
        
        // キャンセルボタン
        let cancelButton = NSButton(frame: NSRect(x: 190, y: 20, width: 90, height: 30))
        cancelButton.title = "キャンセル"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(closeSettingsWindow(_:))
        contentView.addSubview(cancelButton)
        
        window.contentView = contentView
        
        // ウィンドウを表示
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // 修飾キーからインデックスを取得
    private func modifierIndex(_ modifiers: CGEventFlags) -> Int {
        if modifiers.contains(.maskShift) { return 0 }
        if modifiers.contains(.maskControl) { return 1 }
        if modifiers.contains(.maskCommand) { return 2 }
        if modifiers.contains(.maskAlternate) { return 3 }
        return 0
    }
    
    // キーコードからインデックスを取得
    private func keyIndex(_ keyCode: CGKeyCode) -> Int {
        switch keyCode {
        case 49: return 0  // Space
        case 36: return 1  // Return
        case 0: return 2   // A
        case 11: return 3  // B
        case 8: return 4   // C
        default: return 0
        }
    }
    
    @objc private func saveKeyMapping(_ sender: NSButton) {
        // 設定ウィンドウから値を取得
        guard let window = sender.window,
              let contentView = window.contentView else { return }
        
        // 各ポップアップボタンを取得
        let sourceModifierPopup = contentView.subviews.first { $0.tag == 1 } as? NSPopUpButton
        let sourceKeyPopup = contentView.subviews.first { $0.tag == 2 } as? NSPopUpButton
        let targetModifierPopup = contentView.subviews.first { $0.tag == 3 } as? NSPopUpButton
        let targetKeyPopup = contentView.subviews.first { $0.tag == 4 } as? NSPopUpButton
        
        guard let sourceMod = sourceModifierPopup?.titleOfSelectedItem,
              let sourceK = sourceKeyPopup?.titleOfSelectedItem,
              let targetMod = targetModifierPopup?.titleOfSelectedItem,
              let targetK = targetKeyPopup?.titleOfSelectedItem else { return }
        
        // 選択された値をKeyMappingに変換
        let newMapping = KeyMapping(
            sourceModifiers: modifierFlagFromName(sourceMod),
            sourceKey: keyCodeFromName(sourceK),
            targetModifiers: modifierFlagFromName(targetMod),
            targetKey: keyCodeFromName(targetK)
        )
        
        // すべての処理をメインスレッドで実行
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // ウィンドウを閉じる
            window.close()
            
            // 設定を更新
            self.currentMapping = newMapping
            self.saveMapping()  // UserDefaultsに保存
            
            // KeyRemapperを再起動
            self.keyRemapper?.stop()  // 古いものを停止
            self.keyRemapper = KeyRemapper(mapping: self.currentMapping)
            // 監視中のフロントアプリIDも渡し直す
            self.keyRemapper?.setFrontmostBundleID(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            self.keyRemapper?.setXcodeOnly((self.statusItem?.menu?.items.first { $0.title == "設定" }?.submenu?.items.first { $0.title == "Xcode専用モード" }?.state ?? .off) == .on)
            self.keyRemapper?.setEnabled(self.isEnabled)
            self.keyRemapper?.start()  // 新しいものを起動
            
            print("keyRemapper restarted")
            
            // メニューの情報表示も更新
            self.updateMenuInfo()
        }
    }
    
    @objc private func closeSettingsWindow(_ sender: NSButton) {
        sender.window?.close()
    }
    
    // 修飾キー名からCGEventFlagsに変換
    private func modifierFlagFromName(_ name: String) -> CGEventFlags {
        switch name {
        case "Shift": return .maskShift
        case "Control": return .maskControl
        case "Command": return .maskCommand
        case "Option": return .maskAlternate
        default: return []
        }
    }
    
    // キー名からキーコードに変換
    private func keyCodeFromName(_ name: String) -> CGKeyCode {
        switch name {
        case "Space": return 49
        case "Return": return 36
        case "A": return 0
        case "B": return 11
        case "C": return 8
        default: return 49
        }
    }
    
    // メニューの情報表示を更新
    private func updateMenuInfo() {
        guard let _ = statusItem?.menu else { return }
        // 新しいメニューを再構築する方が安全
        setupMenu()
    }
    
    // 修飾キーの名前を取得
    private func modifierName(_ modifiers: CGEventFlags) -> String {
        var names: [String] = []
        if modifiers.contains(.maskShift) { names.append("Shift") }
        if modifiers.contains(.maskControl) { names.append("Control") }
        if modifiers.contains(.maskCommand) { names.append("Command") }
        if modifiers.contains(.maskAlternate) { names.append("Option") }
        return names.isEmpty ? "なし" : names.joined(separator: "+")
    }
    
    // キーの名前を取得（簡易版）
    private func keyName(_ keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 51: return "Delete"
        case 53: return "Escape"
        case 0: return "A"
        case 11: return "B"
        case 8: return "C"
        default: return "キーコード \(keyCode)"
        }
    }
    
    // macOS 13+ ログイン項目の状態
    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

class KeyRemapper {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    
    private var isEnabled = true
    private var xcodeOnly = false
    private var mapping: KeyMapping
    
    // イベントタップからは AppKit を触らないため、フロントアプリIDは別途キャッシュ
    private let stateQueue = DispatchQueue(label: "KeyRemapper.state.queue", qos: .userInteractive)
    private var frontmostBundleID: String?
    
    init(mapping: KeyMapping){
        self.mapping = mapping
    }
    
    func start() {
        // すでに起動済みなら何もしない
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
        // このスレッドのランループを取得
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
        
        // このスレッドのランループを回す
        CFRunLoopRun()
        
        // ループ終了時のクリーンアップ
        if let source = self.runLoopSource {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        self.runLoopSource = nil
        self.eventTap = nil
        self.tapRunLoop = nil
    }
    
    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 無効化されている場合はスルー
        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }
        
        // Xcode専用モードの場合、キャッシュ済みのフロントアプリIDで判定（AppKitを触らない）
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
            // 必要な修飾キーが押されているかチェック
            let hasRequiredModifiers = checkModifiers(flags: flags, required: mapping.sourceModifiers)
            
            if hasRequiredModifiers {
                // イベントのコピーを作成
                guard let newEvent = event.copy() else {
                    return Unmanaged.passUnretained(event)
                }
                
                // 修飾キーをクリアしてから新しい修飾キーを設定
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

// エントリーポイント
@main
struct SktdrKanaApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
