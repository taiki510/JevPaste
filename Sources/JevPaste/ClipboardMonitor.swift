import AppKit

final class ClipboardMonitor {
    var isPaused = false

    private let store: EncryptedHistoryStore
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var internalChangeDepth = 0

    init(store: EncryptedHistoryStore) {
        self.store = store
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.captureIfChanged()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func synchronizeChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func beginInternalChange() {
        internalChangeDepth += 1
    }

    func endInternalChange(synchronize: Bool) {
        internalChangeDepth = max(0, internalChangeDepth - 1)
        if synchronize { synchronizeChangeCount() }
    }

    func currentTextCopy() -> Clip? {
        let pasteboard = NSPasteboard.general
        guard internalChangeDepth == 0,
              let rawText = pasteboard.string(forType: .string),
              let text = SensitiveDataFilter.sanitizedCandidate(rawText)
        else { return nil }

        lastChangeCount = pasteboard.changeCount
        if let latest = store.latestCopy(), latest.text == text {
            return latest
        }

        if !isPaused {
            store.add(text: text, sourceApp: "Current clipboard")
            return store.latestCopy()
        }

        return Clip(id: UUID(), text: text, sourceApp: "Current clipboard", createdAt: Date())
    }

    private func captureIfChanged() {
        let pasteboard = NSPasteboard.general
        guard internalChangeDepth == 0 else { return }
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !isPaused, let text = pasteboard.string(forType: .string)
        else { return }
        let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        store.add(text: text, sourceApp: source)
    }
}
