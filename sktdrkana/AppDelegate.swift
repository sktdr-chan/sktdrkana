import Cocoa
import ApplicationServices
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var keyRemapper: KeyRemapper?
    private var isEnabled = true
    private var currentMapping: KeyMapping = KeyMapping.defaultMapping
    private var reverseMouseScroll = false
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var workspaceObserver: NSObjectProtocol?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        currentMapping = UserDefaultsManager.load()
        reverseMouseScroll = UserDefaultsManager.loadReverseMouseScroll()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = false
        }
        
        setupMenu()
        
        keyRemapper = KeyRemapper(mapping: currentMapping)
        keyRemapper?.setReverseMouseScroll(reverseMouseScroll)
        
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.keyRemapper?.setFrontmostBundleID(app?.bundleIdentifier)
        }
        keyRemapper?.setFrontmostBundleID(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        
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
        
        keyRemapper?.start()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        let aboutItem = NSMenuItem(
            title: "About sktdrkana",
            action: #selector(openAboutWindow),
            keyEquivalent: ""
        )
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem.separator())
        
        let toggleItem = NSMenuItem(
            title: "リマッピング: 有効",
            action: #selector(toggleRemapping),
            keyEquivalent: ""
        )
        toggleItem.state = .on
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "設定", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        
        let keyMappingItem = NSMenuItem(
            title: "キーマッピング設定...",
            action: #selector(openKeyMappingSettings),
            keyEquivalent: ""
        )
        settingsMenu.addItem(keyMappingItem)
        
        let reverseScrollItem = NSMenuItem(
            title: "マウスのスクロールの向きを逆にする",
            action: #selector(toggleReverseMouseScroll),
            keyEquivalent: ""
        )
        reverseScrollItem.state = reverseMouseScroll ? .on : .off
        settingsMenu.addItem(reverseScrollItem)
        
        settingsMenu.addItem(NSMenuItem.separator())
        
        let xcodeOnlyItem = NSMenuItem(
            title: "Xcode専用モード",
            action: #selector(toggleXcodeOnly),
            keyEquivalent: ""
        )
        xcodeOnlyItem.state = .off
        settingsMenu.addItem(xcodeOnlyItem)
        
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
        
        let statusMenuItem = NSMenuItem(
            title: "状態: 動作中",
            action: nil,
            keyEquivalent: ""
        )
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let infoItem = NSMenuItem(
            title: "\(KeyCodeMapper.modifierName(currentMapping.sourceModifiers))+\(KeyCodeMapper.keyName(currentMapping.sourceKey)) → \(KeyCodeMapper.modifierName(currentMapping.targetModifiers))+\(KeyCodeMapper.keyName(currentMapping.targetKey))",
            action: nil,
            keyEquivalent: ""
        )
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        
        menu.addItem(NSMenuItem.separator())
        
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
        
        let iconImageView = NSImageView(frame: NSRect(x: 20, y: 220, width: 64, height: 64))
        iconImageView.image = NSApp.applicationIconImage
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(iconImageView)
        
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "sktdrkana"
        let titleLabel = NSTextField(labelWithString: appName)
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.frame = NSRect(x: 100, y: 260, width: 360, height: 24)
        contentView.addSubview(titleLabel)
        
        let versionLabel = NSTextField(labelWithString: appVersionString())
        versionLabel.frame = NSRect(x: 100, y: 236, width: 360, height: 18)
        contentView.addSubview(versionLabel)
        
        let textView = NSTextView(frame: NSRect(x: 20, y: 20, width: 440, height: 150))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textStorage?.setAttributedString(makeAboutAttributedString())
        contentView.addSubview(textView)
        
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
    
    @objc private func toggleReverseMouseScroll(_ sender: NSMenuItem) {
        reverseMouseScroll.toggle()
        sender.state = reverseMouseScroll ? .on : .off
        UserDefaultsManager.saveReverseMouseScroll(reverseMouseScroll)
        keyRemapper?.setReverseMouseScroll(reverseMouseScroll)
    }
    
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
    
    @objc private func openKeyMappingSettings() {
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
        
        let contentView = NSView(frame: window.contentView!.bounds)
        
        let titleLabel = NSTextField(labelWithString: "入力するキーの組み合わせ:")
        titleLabel.frame = NSRect(x: 20, y: 240, width: 360, height: 20)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        contentView.addSubview(titleLabel)
        
        let sourceModifierLabel = NSTextField(labelWithString: "修飾キー:")
        sourceModifierLabel.frame = NSRect(x: 20, y: 210, width: 80, height: 20)
        contentView.addSubview(sourceModifierLabel)
        
        let sourceModifierPopup = NSPopUpButton(frame: NSRect(x: 110, y: 205, width: 150, height: 25))
        sourceModifierPopup.addItems(withTitles: ["Shift", "Control", "Command", "Option"])
        let sourceModIndex = KeyCodeMapper.modifierIndex(currentMapping.sourceModifiers)
        if sourceModIndex < sourceModifierPopup.numberOfItems {
            sourceModifierPopup.selectItem(at: sourceModIndex)
        }
        sourceModifierPopup.tag = 1
        contentView.addSubview(sourceModifierPopup)
        
        let sourceKeyLabel = NSTextField(labelWithString: "キー:")
        sourceKeyLabel.frame = NSRect(x: 20, y: 180, width: 80, height: 20)
        contentView.addSubview(sourceKeyLabel)
        
        let sourceKeyPopup = NSPopUpButton(frame: NSRect(x: 110, y: 175, width: 150, height: 25))
        sourceKeyPopup.addItems(withTitles: ["Space", "Return", "A", "B", "C"])
        let sourceKeyIndex = KeyCodeMapper.keyIndex(currentMapping.sourceKey)
        if sourceKeyIndex < sourceKeyPopup.numberOfItems {
            sourceKeyPopup.selectItem(at: sourceKeyIndex)
        }
        sourceKeyPopup.tag = 2
        contentView.addSubview(sourceKeyPopup)
        
        let arrowLabel = NSTextField(labelWithString: "↓ 変換後 ↓")
        arrowLabel.frame = NSRect(x: 20, y: 145, width: 360, height: 20)
        arrowLabel.alignment = .center
        arrowLabel.font = NSFont.systemFont(ofSize: 12)
        contentView.addSubview(arrowLabel)
        
        let titleLabel2 = NSTextField(labelWithString: "出力するキーの組み合わせ:")
        titleLabel2.frame = NSRect(x: 20, y: 115, width: 360, height: 20)
        titleLabel2.font = NSFont.boldSystemFont(ofSize: 13)
        contentView.addSubview(titleLabel2)
        
        let targetModifierLabel = NSTextField(labelWithString: "修飾キー:")
        targetModifierLabel.frame = NSRect(x: 20, y: 85, width: 80, height: 20)
        contentView.addSubview(targetModifierLabel)
        
        let targetModifierPopup = NSPopUpButton(frame: NSRect(x: 110, y: 80, width: 150, height: 25))
        targetModifierPopup.addItems(withTitles: ["Shift", "Control", "Command", "Option"])
        let targetModIndex = KeyCodeMapper.modifierIndex(currentMapping.targetModifiers)
        if targetModIndex < targetModifierPopup.numberOfItems {
            targetModifierPopup.selectItem(at: targetModIndex)
        }
        targetModifierPopup.tag = 3
        contentView.addSubview(targetModifierPopup)
        
        let targetKeyLabel = NSTextField(labelWithString: "キー:")
        targetKeyLabel.frame = NSRect(x: 20, y: 55, width: 80, height: 20)
        contentView.addSubview(targetKeyLabel)
        
        let targetKeyPopup = NSPopUpButton(frame: NSRect(x: 110, y: 50, width: 150, height: 25))
        targetKeyPopup.addItems(withTitles: ["Space", "Return", "A", "B", "C"])
        let targetKeyIndex = KeyCodeMapper.keyIndex(currentMapping.targetKey)
        if targetKeyIndex < targetKeyPopup.numberOfItems {
            targetKeyPopup.selectItem(at: targetKeyIndex)
        }
        targetKeyPopup.tag = 4
        contentView.addSubview(targetKeyPopup)
        
        let saveButton = NSButton(frame: NSRect(x: 290, y: 20, width: 90, height: 30))
        saveButton.title = "保存"
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveKeyMapping(_:))
        contentView.addSubview(saveButton)
        
        let cancelButton = NSButton(frame: NSRect(x: 190, y: 20, width: 90, height: 30))
        cancelButton.title = "キャンセル"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(closeSettingsWindow(_:))
        contentView.addSubview(cancelButton)
        
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func saveKeyMapping(_ sender: NSButton) {
        guard let window = sender.window,
              let contentView = window.contentView else { return }
        
        let sourceModifierPopup = contentView.subviews.first { $0.tag == 1 } as? NSPopUpButton
        let sourceKeyPopup = contentView.subviews.first { $0.tag == 2 } as? NSPopUpButton
        let targetModifierPopup = contentView.subviews.first { $0.tag == 3 } as? NSPopUpButton
        let targetKeyPopup = contentView.subviews.first { $0.tag == 4 } as? NSPopUpButton
        
        guard let sourceMod = sourceModifierPopup?.titleOfSelectedItem,
              let sourceK = sourceKeyPopup?.titleOfSelectedItem,
              let targetMod = targetModifierPopup?.titleOfSelectedItem,
              let targetK = targetKeyPopup?.titleOfSelectedItem else { return }
        
        let newMapping = KeyMapping(
            sourceModifiers: KeyCodeMapper.modifierFlagFromName(sourceMod),
            sourceKey: KeyCodeMapper.keyCodeFromName(sourceK),
            targetModifiers: KeyCodeMapper.modifierFlagFromName(targetMod),
            targetKey: KeyCodeMapper.keyCodeFromName(targetK)
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            window.close()
            
            self.currentMapping = newMapping
            UserDefaultsManager.save(mapping: self.currentMapping)
            
            self.keyRemapper?.stop()
            self.keyRemapper = KeyRemapper(mapping: self.currentMapping)
            self.keyRemapper?.setFrontmostBundleID(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            self.keyRemapper?.setXcodeOnly((self.statusItem?.menu?.items.first { $0.title == "設定" }?.submenu?.items.first { $0.title == "Xcode専用モード" }?.state ?? .off) == .on)
            self.keyRemapper?.setReverseMouseScroll(self.reverseMouseScroll)
            self.keyRemapper?.setEnabled(self.isEnabled)
            self.keyRemapper?.start()
            
            print("keyRemapper restarted")
            
            self.setupMenu()
        }
    }
    
    @objc private func closeSettingsWindow(_ sender: NSButton) {
        sender.window?.close()
    }
    
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
