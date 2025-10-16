import Cocoa
import ApplicationServices
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var keyRemapper: KeyRemapper?
    private var isEnabled = true
    private var currentMappings: [KeyMapping] = []
    private var reverseMouseScroll = false
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var workspaceObserver: NSObjectProtocol?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        var loadedMappings = UserDefaultsManager.load()
        
        // 初回起動時（デフォルトマッピングのみ）の場合、マッピング1のみ有効に
        if loadedMappings.count == 1 && loadedMappings[0].id == KeyMapping.defaultMapping.id {
            loadedMappings[0].enabled = true
        }
        
        currentMappings = loadedMappings
        reverseMouseScroll = UserDefaultsManager.loadReverseMouseScroll()
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = false
        }
        
        setupMenu()
        
        keyRemapper = KeyRemapper(mappings: currentMappings)
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
        
        // 複数マッピングをすべて表示
        for (index, mapping) in currentMappings.enumerated() {
            let enabledText = mapping.enabled ? "" : " [無効]"
            let mappingText = "\(index + 1). \(KeyCodeMapper.modifierName(mapping.sourceModifiers))+\(KeyCodeMapper.keyName(mapping.sourceKey)) → \(KeyCodeMapper.modifierName(mapping.targetModifiers))+\(KeyCodeMapper.keyName(mapping.targetKey))\(enabledText)"
            let infoItem = NSMenuItem(
                title: mappingText,
                action: nil,
                keyEquivalent: ""
            )
            infoItem.isEnabled = false
            menu.addItem(infoItem)
        }
        
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
        複数のキーマッピング（最大4個）に対応しました。
        
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
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 400),
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
        
        let titleLabel = NSTextField(labelWithString: "キーマッピング設定（最大4個まで設定可能）")
        titleLabel.frame = NSRect(x: 20, y: 360, width: 760, height: 20)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        contentView.addSubview(titleLabel)
        
        var yPosition = 305  // 上から 305 の位置から開始
        // 常に4つのマッピング欄を表示
        let mappingsToEdit = (currentMappings + Array(repeating: KeyMapping.defaultMapping, count: max(0, 4 - currentMappings.count))).prefix(4)
        
        for (index, mapping) in mappingsToEdit.enumerated() {
            let mappingView = createMappingEditView(for: index, mapping: mapping, yPosition: yPosition)
            contentView.addSubview(mappingView)
            yPosition -= 60  // 2行分のスペース + 5ドット増
        }
        
        let saveButton = NSButton(frame: NSRect(x: 800, y: 15, width: 80, height: 30))
        saveButton.title = "保存"
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveMultipleKeyMappings(_:))
        contentView.addSubview(saveButton)
        
        let cancelButton = NSButton(frame: NSRect(x: 710, y: 15, width: 80, height: 30))
        cancelButton.title = "キャンセル"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(closeSettingsWindow(_:))
        contentView.addSubview(cancelButton)
        
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func createMappingEditView(for index: Int, mapping: KeyMapping, yPosition: Int) -> NSView {
        let view = NSView(frame: NSRect(x: 20, y: yPosition - 25, width: 860, height: 55))
        
        // チェックボックス（左端）
        let checkbox = NSButton(frame: NSRect(x: 5, y: 30, width: 20, height: 20))
        checkbox.setButtonType(.switch)
        checkbox.state = mapping.enabled ? .on : .off
        checkbox.tag = 200 + index
        view.addSubview(checkbox)
        
        let label = NSTextField(labelWithString: "マッピング \(index + 1):")
        label.frame = NSRect(x: 30, y: 30, width: 100, height: 18)
        label.font = NSFont.boldSystemFont(ofSize: 12)
        view.addSubview(label)
        
        // 1行目：入力 修飾キー1, キー1
        let sourceModLabel = NSTextField(labelWithString: "入力:")
        sourceModLabel.frame = NSRect(x: 135, y: 30, width: 40, height: 18)
        view.addSubview(sourceModLabel)
        
        let sourceModPopup = NSPopUpButton(frame: NSRect(x: 180, y: 25, width: 95, height: 25))
        sourceModPopup.addItems(withTitles: ["Shift", "Control", "Command", "Option", "None"])
        sourceModPopup.selectItem(at: KeyCodeMapper.modifierIndex(mapping.sourceModifiers))
        sourceModPopup.tag = 100 + index * 8
        styleNoneInPopup(sourceModPopup)
        view.addSubview(sourceModPopup)
        
        let sourceKeyPopup = NSPopUpButton(frame: NSRect(x: 280, y: 25, width: 95, height: 25))
        sourceKeyPopup.addItems(withTitles: ["Space", "Return", "Delete", "Escape", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "None"])
        sourceKeyPopup.selectItem(at: KeyCodeMapper.keyIndex(mapping.sourceKey))
        sourceKeyPopup.tag = 101 + index * 8
        styleNoneInPopup(sourceKeyPopup)
        view.addSubview(sourceKeyPopup)
        
        let arrowLabel = NSTextField(labelWithString: "→")
        arrowLabel.frame = NSRect(x: 380, y: 30, width: 20, height: 18)
        arrowLabel.alignment = .center
        arrowLabel.font = NSFont.systemFont(ofSize: 14)
        view.addSubview(arrowLabel)
        
        // 1行目：出力 修飾キー, キー
        let targetModLabel = NSTextField(labelWithString: "出力:")
        targetModLabel.frame = NSRect(x: 405, y: 30, width: 40, height: 18)
        view.addSubview(targetModLabel)
        
        let targetModPopup = NSPopUpButton(frame: NSRect(x: 450, y: 25, width: 95, height: 25))
        targetModPopup.addItems(withTitles: ["Shift", "Control", "Command", "Option", "None"])
        targetModPopup.selectItem(at: KeyCodeMapper.modifierIndex(mapping.targetModifiers))
        targetModPopup.tag = 102 + index * 8
        styleNoneInPopup(targetModPopup)
        view.addSubview(targetModPopup)
        
        let targetKeyPopup = NSPopUpButton(frame: NSRect(x: 550, y: 25, width: 95, height: 25))
        targetKeyPopup.addItems(withTitles: ["Space", "Return", "Delete", "Escape", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "None"])
        targetKeyPopup.selectItem(at: KeyCodeMapper.keyIndex(mapping.targetKey))
        targetKeyPopup.tag = 103 + index * 8
        styleNoneInPopup(targetKeyPopup)
        view.addSubview(targetKeyPopup)
        
        // 2行目のラベル
        let mod2Popup = NSPopUpButton(frame: NSRect(x: 180, y: 0, width: 95, height: 25))
        mod2Popup.addItems(withTitles: ["Space", "Return", "Delete", "Escape", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "None"])
        mod2Popup.selectItem(at: 30)  // Default: None
        mod2Popup.tag = 104 + index * 8
        styleNoneInPopup(mod2Popup)
        view.addSubview(mod2Popup)
        
        let key2Popup = NSPopUpButton(frame: NSRect(x: 280, y: 0, width: 95, height: 25))
        key2Popup.addItems(withTitles: ["Space", "Return", "Delete", "Escape", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "None"])
        key2Popup.selectItem(at: 30)  // Default: None
        key2Popup.tag = 105 + index * 8
        styleNoneInPopup(key2Popup)
        view.addSubview(key2Popup)
        
        let targetMod2Popup = NSPopUpButton(frame: NSRect(x: 450, y: 0, width: 95, height: 25))
        targetMod2Popup.addItems(withTitles: ["Shift", "Control", "Command", "Option", "None"])
        targetMod2Popup.selectItem(at: 4)  // Default: None
        targetMod2Popup.tag = 106 + index * 8
        styleNoneInPopup(targetMod2Popup)
        view.addSubview(targetMod2Popup)
        
        let targetKey2Popup = NSPopUpButton(frame: NSRect(x: 550, y: 0, width: 95, height: 25))
        targetKey2Popup.addItems(withTitles: ["Space", "Return", "Delete", "Escape", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "None"])
        targetKey2Popup.selectItem(at: 30)  // Default: None
        targetKey2Popup.tag = 107 + index * 8
        styleNoneInPopup(targetKey2Popup)
        view.addSubview(targetKey2Popup)
        
        return view
    }
    
    private func styleNoneInPopup(_ popup: NSPopUpButton) {
        // 鯉色を設定
        let grayColor = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        
        if let menu = popup.menu {
            for item in menu.items {
                if item.title == "None" {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .foregroundColor: grayColor
                    ]
                    item.attributedTitle = NSAttributedString(string: "None", attributes: attributes)
                }
            }
        }
    }
    
    @objc private func saveMultipleKeyMappings(_ sender: NSButton) {
        guard let window = sender.window,
              let contentView = window.contentView else { return }
        
        var newMappings: [KeyMapping] = []
        
        for index in 0..<4 {
            let checkbox = findButton(in: contentView, tag: 200 + index)
            let sourceMod = findPopupButton(in: contentView, tag: 100 + index * 8)
            let sourceKey = findPopupButton(in: contentView, tag: 101 + index * 8)
            let targetMod = findPopupButton(in: contentView, tag: 102 + index * 8)
            let targetKey = findPopupButton(in: contentView, tag: 103 + index * 8)
            
            if let sourceMod = sourceMod?.titleOfSelectedItem,
               let sourceKey = sourceKey?.titleOfSelectedItem,
               let targetMod = targetMod?.titleOfSelectedItem,
               let targetKey = targetKey?.titleOfSelectedItem,
               !(sourceMod.isEmpty || sourceKey.isEmpty || targetMod.isEmpty || targetKey.isEmpty),
               sourceMod != "None" || sourceKey != "None" {
                
                let enabled = (checkbox?.state ?? .off) == .on
                
                let mapping = KeyMapping(
                    sourceModifiers: KeyCodeMapper.modifierFlagFromName(sourceMod),
                    sourceKey: KeyCodeMapper.keyCodeFromName(sourceKey),
                    targetModifiers: KeyCodeMapper.modifierFlagFromName(targetMod),
                    targetKey: KeyCodeMapper.keyCodeFromName(targetKey),
                    enabled: enabled
                )
                newMappings.append(mapping)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            window.close()
            
            self.currentMappings = newMappings
            UserDefaultsManager.save(mappings: self.currentMappings)
            
            self.keyRemapper?.stop()
            self.keyRemapper = KeyRemapper(mappings: self.currentMappings)
            self.keyRemapper?.setFrontmostBundleID(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            self.keyRemapper?.setXcodeOnly((self.statusItem?.menu?.items.first { $0.title == "設定" }?.submenu?.items.first { $0.title == "Xcode専用モード" }?.state ?? .off) == .on)
            self.keyRemapper?.setReverseMouseScroll(self.reverseMouseScroll)
            self.keyRemapper?.setEnabled(self.isEnabled)
            self.keyRemapper?.start()
            
            print("複数マッピング設定が保存されました: \(self.currentMappings.count)個（有効: \(self.currentMappings.filter { $0.enabled }.count)個）")
            
            self.setupMenu()
        }
    }
    
    private func findPopupButton(in view: NSView, tag: Int) -> NSPopUpButton? {
        for subview in view.subviews {
            if let popup = subview as? NSPopUpButton, popup.tag == tag {
                return popup
            }
            if let scrollView = subview as? NSScrollView,
               let documentView = scrollView.contentView.documentView {
                return findPopupButton(in: documentView, tag: tag)
            }
            if let found = findPopupButton(in: subview, tag: tag) {
                return found
            }
        }
        return nil
    }
    
    private func findButton(in view: NSView, tag: Int) -> NSButton? {
        for subview in view.subviews {
            if let button = subview as? NSButton, button.tag == tag {
                return button
            }
            if let scrollView = subview as? NSScrollView,
               let documentView = scrollView.contentView.documentView {
                return findButton(in: documentView, tag: tag)
            }
            if let found = findButton(in: subview, tag: tag) {
                return found
            }
        }
        return nil
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
