import AppKit

enum ProfileEditor {
    static func edit(currentText: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Smart Pasteプロフィール"
        alert.informativeText = "ここに保存した全文を、⌘⇧Jの実行時だけTypeSafeのJevへ送信します。空欄で保存すると登録を解除します。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "キャンセル")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 340))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.string = currentText
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
