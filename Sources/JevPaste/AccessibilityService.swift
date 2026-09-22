import AppKit
import ApplicationServices

final class AccessibilityService {
    var isTrusted: Bool { AXIsProcessTrusted() }
    var canMonitorKeyboard: Bool { CGPreflightListenEventAccess() }
    private(set) var lastFocusDiagnostic = "未実行"
    private(set) var lastInsertDiagnostic = "未実行"

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestListenEventAccess()
    }

    func focusedField(targetPID: pid_t? = nil) -> FocusedFieldContext? {
        guard AXIsProcessTrusted() else {
            lastFocusDiagnostic = "アクセシビリティ未許可"
            return nil
        }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 1.5)

        var element: AXUIElement?
        if let targetPID, targetPID != ProcessInfo.processInfo.processIdentifier {
            let application = AXUIElementCreateApplication(targetPID)
            AXUIElementSetMessagingTimeout(application, 1.5)
            element = focusedElement(in: application)
        }
        if element == nil, let focusedApplication = elementAttribute(kAXFocusedApplicationAttribute, of: system) {
            AXUIElementSetMessagingTimeout(focusedApplication, 1.5)
            element = focusedElement(in: focusedApplication)
        }
        if element == nil {
            element = focusedElement(in: system)
        }
        guard let element else {
            let targetName = targetPID.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "不明"
            lastFocusDiagnostic = "対象アプリ \(targetName) (PID \(targetPID ?? 0)) のフォーカス要素を取得できませんでした"
            return nil
        }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let runningApplication = NSRunningApplication(processIdentifier: pid)
        let app = runningApplication?.localizedName ?? "Unknown"
        let bundleIdentifier = runningApplication?.bundleIdentifier ?? ""
        let role = stringAttribute(kAXRoleAttribute, of: element)
        let subrole = stringAttribute(kAXSubroleAttribute, of: element)
        let labelParts = contextualLabels(for: element)
        let webContent = isWebContent(element: element, bundleIdentifier: bundleIdentifier)
        lastFocusDiagnostic = "取得成功: \(app) / \(role) / \(webContent ? "Web" : "Native") / \(labelParts.first ?? "ラベルなし")"
        return FocusedFieldContext(
            element: element,
            label: Array(NSOrderedSet(array: labelParts)).compactMap { $0 as? String }.joined(separator: " · "),
            role: role,
            subrole: subrole,
            app: app,
            bundleIdentifier: bundleIdentifier,
            isWebContent: webContent
        )
    }

    func insert(
        _ text: String,
        into context: FocusedFieldContext,
        monitor: ClipboardMonitor,
        completion: @escaping (Bool) -> Void
    ) {
        if context.isWebContent {
            pasteUsingKeyboard(text, into: context, monitor: monitor, completion: completion)
            return
        }

        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            context.element,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success, settable.boolValue,
           AXUIElementSetAttributeValue(
            context.element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
           ) == .success {
            lastInsertDiagnostic = "AXSelectedTextが入力を受理（追加ペーストなし）"
            completion(true)
            return
        }

        let existingValue = stringAttribute(kAXValueAttribute, of: context.element)
        if existingValue.isEmpty {
            var valueSettable = DarwinBoolean(false)
            if AXUIElementIsAttributeSettable(
                context.element,
                kAXValueAttribute as CFString,
                &valueSettable
            ) == .success, valueSettable.boolValue,
               AXUIElementSetAttributeValue(
                context.element,
                kAXValueAttribute as CFString,
                text as CFTypeRef
               ) == .success {
                lastInsertDiagnostic = "AXValueが入力を受理（追加ペーストなし）"
                completion(true)
                return
            }
        }

        pasteUsingKeyboard(text, into: context, monitor: monitor, completion: completion)
    }

    private func pasteUsingKeyboard(
        _ text: String,
        into context: FocusedFieldContext,
        monitor: ClipboardMonitor,
        completion: @escaping (Bool) -> Void
    ) {
        _ = AXUIElementSetAttributeValue(
            context.element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )

        let snapshot = PasteboardSnapshot.capture()
        let pasteboard = NSPasteboard.general
        monitor.beginInternalChange()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let temporaryChangeCount = pasteboard.changeCount
        monitor.synchronizeChangeCount()

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            snapshot.restore()
            monitor.endInternalChange(synchronize: true)
            lastInsertDiagnostic = "ペースト用キーボードイベントを作成できませんでした"
            completion(false)
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let currentValue = self.stringAttribute(kAXValueAttribute, of: context.element)
            let succeeded = currentValue.contains(text)
            if NSPasteboard.general.changeCount == temporaryChangeCount {
                snapshot.restore()
                monitor.endInternalChange(synchronize: true)
            } else {
                // Preserve and subsequently capture a clipboard change made by the user.
                monitor.endInternalChange(synchronize: false)
            }
            self.lastInsertDiagnostic = succeeded
                ? "Command-Vを1回送信して入力成功（\(context.isWebContent ? "Web" : "Native")）"
                : "Command-V送信後に入力を確認できませんでした（\(context.app) / role: \(context.role)）"
            completion(succeeded)
        }
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }

    private func focusedElement(in root: AXUIElement) -> AXUIElement? {
        for _ in 0..<3 {
            if let element = elementAttribute(kAXFocusedUIElementAttribute, of: root) {
                return element
            }
            usleep(30_000)
        }
        return nil
    }

    private func elementAttribute(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func contextualLabels(for element: AXUIElement) -> [String] {
        var labels: [String] = []
        var current: AXUIElement? = element
        for _ in 0..<3 {
            guard let node = current else { break }
            labels.append(contentsOf: [
                stringAttribute(kAXTitleAttribute, of: node),
                stringAttribute(kAXDescriptionAttribute, of: node),
                stringAttribute(kAXPlaceholderValueAttribute, of: node),
                stringAttribute(kAXHelpAttribute, of: node),
                stringAttribute(kAXIdentifierAttribute, of: node),
            ].filter { !$0.isEmpty })
            current = elementAttribute(kAXParentAttribute, of: node)
        }
        return labels
    }

    private func isWebContent(element: AXUIElement, bundleIdentifier: String) -> Bool {
        let browserBundleIDs = [
            "com.brave.Browser",
            "com.google.Chrome",
            "com.apple.Safari",
            "com.microsoft.edgemac",
            "org.mozilla.firefox",
        ]
        if browserBundleIDs.contains(bundleIdentifier) { return true }

        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let node = current else { break }
            if stringAttribute(kAXRoleAttribute, of: node) == "AXWebArea" {
                return true
            }
            current = elementAttribute(kAXParentAttribute, of: node)
        }
        return false
    }
}

private struct PasteboardSnapshot {
    struct Item {
        let values: [(NSPasteboard.PasteboardType, Data)]
    }

    let items: [Item]

    static func capture() -> PasteboardSnapshot {
        let captured = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Item(values: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        return PasteboardSnapshot(items: captured)
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let restored = items.map { source -> NSPasteboardItem in
            let item = NSPasteboardItem()
            source.values.forEach { item.setData($0.1, forType: $0.0) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
