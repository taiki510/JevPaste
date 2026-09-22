import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum PasteSource {
        case clipboard
        case profile
    }

    private enum HotKey: UInt32 {
        case clipboard = 1
        case profile = 2
    }

    private let store = EncryptedHistoryStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    private let accessibility = AccessibilityService()
    private let client = JevClient()
    private lazy var history = HistoryWindowController(store: store)

    private var statusItem: NSStatusItem!
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var clipboardHotKeyRef: EventHotKeyRef?
    private var profileHotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var clipboardHotKeyRegistered = false
    private var profileHotKeyRegistered = false
    private var lastInvocationTime = Date.distantPast
    private var historyMenuItem: NSMenuItem!
    private var pauseMenuItem: NSMenuItem!
    private var requestInFlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        monitor.start()
        installShortcut()
        store.onChange = { [weak self] in self?.history.reload() }
        history.onVisibilityChanged = { [weak self] in self?.updateHistoryMenuTitle() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        if let clipboardHotKeyRef { UnregisterEventHotKey(clipboardHotKeyRef) }
        if let profileHotKeyRef { UnregisterEventHotKey(profileHotKeyRef) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }

    @objc private func smartPasteNow() {
        performSmartPaste(targetPID: nil, source: .clipboard)
    }

    @objc private func smartPasteProfileNow() {
        performSmartPaste(targetPID: nil, source: .profile)
    }

    private func performSmartPaste(targetPID: pid_t?, source: PasteSource) {
        guard !requestInFlight else { return }
        let now = Date()
        guard now.timeIntervalSince(lastInvocationTime) >= 0.75 else { return }
        lastInvocationTime = now
        guard let apiKey = KeychainStore.shared.readAPIKey(), !apiKey.isEmpty else {
            configureAPIKey()
            return
        }
        guard let field = accessibility.focusedField(targetPID: targetPID) else {
            showError(JevPasteError.accessibilityUnavailable)
            return
        }
        guard !SensitiveDataFilter.isSensitiveField(label: field.label, role: field.role, subrole: field.subrole) else {
            showError(JevPasteError.sensitiveField)
            return
        }
        let sourceClip: Clip
        switch source {
        case .clipboard:
            guard let currentCopy = monitor.currentTextCopy() else {
                showError(JevPasteError.emptyHistory)
                return
            }
            sourceClip = currentCopy
        case .profile:
            guard let profile = KeychainStore.shared.readProfile(), !profile.isEmpty else {
                showError(JevPasteError.emptyProfile)
                return
            }
            sourceClip = Clip(id: UUID(), text: profile, sourceApp: "Saved profile", createdAt: Date())
        }

        requestInFlight = true
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "選択中")
        client.choose(field: field, clips: [sourceClip], apiKey: apiKey) { [weak self] result in
            guard let self else { return }
            self.requestInFlight = false
            self.statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "JevPaste")
            switch result {
            case .success(let value):
                self.accessibility.insert(value, into: field, monitor: self.monitor) { succeeded in
                    if !succeeded { self.showError(JevPasteError.insertionFailed) }
                }
            case .failure(let error):
                self.showError(error)
            }
        }
    }

    @objc private func toggleHistory() {
        history.toggle()
    }

    @objc private func editProfile() {
        let current = KeychainStore.shared.readProfile() ?? ""
        guard let edited = ProfileEditor.edit(currentText: current) else { return }
        if edited.isEmpty {
            _ = KeychainStore.shared.removeProfile()
        } else {
            _ = KeychainStore.shared.saveProfile(edited)
        }
    }

    @objc private func configureAPIKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "TypeSafe APIキー"
        alert.informativeText = "キーはこのMacのKeychainだけに保存され、api.typesafe.ai以外には送信されません。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "キャンセル")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "API key"
        field.stringValue = KeychainStore.shared.readAPIKey() ?? ""
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { _ = KeychainStore.shared.saveAPIKey(value) }
    }

    @objc private func removeAPIKey() {
        _ = KeychainStore.shared.removeAPIKey()
    }

    @objc private func toggleCapture() {
        monitor.isPaused.toggle()
        updatePauseMenuTitle()
    }

    @objc private func clearHistory() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "履歴をすべて削除しますか？"
        alert.informativeText = "暗号化されたローカル履歴を削除します。現在のクリップボードは変更しません。"
        alert.addButton(withTitle: "削除")
        alert.addButton(withTitle: "キャンセル")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { store.clear() }
    }

    @objc private func requestAccessibility() {
        accessibility.requestAccess()
    }

    @objc private func showDiagnostics() {
        NSApp.activate(ignoringOtherApps: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let apiKeyStatus = KeychainStore.shared.readAPIKey()?.isEmpty == false ? "設定済み" : "未設定"
        let lines = [
            "バージョン: \(version)",
            "Command-J（クリップボード）: \(clipboardHotKeyRegistered ? "登録済み" : "登録失敗")",
            "Command-Shift-J（プロフィール）: \(profileHotKeyRegistered ? "登録済み" : "登録失敗")",
            "アクセシビリティ: \(accessibility.isTrusted ? "許可済み" : "未許可")",
            "入力監視: \(accessibility.canMonitorKeyboard ? "許可済み" : "未許可（Carbonホットキーでは不要）")",
            "TypeSafe APIキー: \(apiKeyStatus)",
            "プロフィール: \(KeychainStore.shared.readProfile()?.isEmpty == false ? "設定済み" : "未設定")",
            "履歴: \(store.clips.count)件",
            "直近の入力欄取得: \(accessibility.lastFocusDiagnostic)",
            "直近の入力処理: \(accessibility.lastInsertDiagnostic)",
        ]
        let alert = NSAlert()
        alert.messageText = "JevPaste 診断"
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "JevPaste")

        let menu = NSMenu()
        let paste = NSMenuItem(title: "Smart Paste（⌘J）", action: #selector(smartPasteNow), keyEquivalent: "")
        paste.target = self
        menu.addItem(paste)

        let profilePaste = NSMenuItem(title: "プロフィールからSmart Paste（⌘⇧J）", action: #selector(smartPasteProfileNow), keyEquivalent: "")
        profilePaste.target = self
        menu.addItem(profilePaste)

        let editProfile = NSMenuItem(title: "プロフィールを編集…", action: #selector(self.editProfile), keyEquivalent: "")
        editProfile.target = self
        menu.addItem(editProfile)
        menu.addItem(.separator())

        historyMenuItem = NSMenuItem(title: "履歴を開く", action: #selector(toggleHistory), keyEquivalent: "")
        historyMenuItem.target = self
        menu.addItem(historyMenuItem)
        menu.addItem(.separator())

        let configure = NSMenuItem(title: "TypeSafe APIキーを設定…", action: #selector(configureAPIKey), keyEquivalent: "")
        configure.target = self
        menu.addItem(configure)
        let remove = NSMenuItem(title: "APIキーを削除", action: #selector(removeAPIKey), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        menu.addItem(.separator())

        pauseMenuItem = NSMenuItem(title: "クリップボード記録を一時停止", action: #selector(toggleCapture), keyEquivalent: "")
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)
        let clear = NSMenuItem(title: "履歴をすべて削除…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        let permission = NSMenuItem(title: "操作・入力監視権限を確認…", action: #selector(requestAccessibility), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)
        let diagnostics = NSMenuItem(title: "接続・権限を診断…", action: #selector(showDiagnostics), keyEquivalent: "")
        diagnostics.target = self
        menu.addItem(diagnostics)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "JevPasteを終了", action: #selector(self.quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func installShortcut() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                var identifier = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard parameterStatus == noErr, let hotKey = HotKey(rawValue: identifier.id) else {
                    return OSStatus(eventNotHandledErr)
                }
                let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let source: PasteSource = hotKey == .profile ? .profile : .clipboard
                DispatchQueue.main.async { delegate.performSmartPaste(targetPID: targetPID, source: source) }
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandler
        )
        if handlerStatus == noErr {
            let clipboardIdentifier = EventHotKeyID(signature: OSType(0x4A565054), id: HotKey.clipboard.rawValue) // JVPT
            let clipboardStatus = RegisterEventHotKey(
                UInt32(kVK_ANSI_J),
                UInt32(cmdKey),
                clipboardIdentifier,
                GetApplicationEventTarget(),
                0,
                &clipboardHotKeyRef
            )
            clipboardHotKeyRegistered = clipboardStatus == noErr

            let profileIdentifier = EventHotKeyID(signature: OSType(0x4A565054), id: HotKey.profile.rawValue)
            let profileStatus = RegisterEventHotKey(
                UInt32(kVK_ANSI_J),
                UInt32(cmdKey | shiftKey),
                profileIdentifier,
                GetApplicationEventTarget(),
                0,
                &profileHotKeyRef
            )
            profileHotKeyRegistered = profileStatus == noErr

            if clipboardHotKeyRegistered && profileHotKeyRegistered { return }
        }

        // Fallback only for a shortcut whose Carbon registration is unavailable.
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleFallbackShortcut(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleFallbackShortcut(event) == true {
                return nil
            }
            return event
        }
    }

    @discardableResult
    private func handleFallbackShortcut(_ event: NSEvent) -> Bool {
        guard event.keyCode == UInt16(kVK_ANSI_J) else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let source: PasteSource
        if flags == .command, !clipboardHotKeyRegistered {
            source = .clipboard
        } else if flags == [.command, .shift], !profileHotKeyRegistered {
            source = .profile
        } else {
            return false
        }
        let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        DispatchQueue.main.async { self.performSmartPaste(targetPID: targetPID, source: source) }
        return true
    }

    private func updateHistoryMenuTitle() {
        historyMenuItem.title = history.isVisible ? "履歴を閉じる" : "履歴を開く"
    }

    private func updatePauseMenuTitle() {
        pauseMenuItem.title = monitor.isPaused ? "クリップボード記録を再開" : "クリップボード記録を一時停止"
    }

    private func showError(_ error: Error) {
        NSSound.beep()
        let alert = NSAlert(error: error)
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
