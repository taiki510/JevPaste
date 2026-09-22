import CryptoKit
import Foundation

final class EncryptedHistoryStore {
    private(set) var clips: [Clip] = []
    var onChange: (() -> Void)?

    private let queue = DispatchQueue(label: "local.taikigoto.jevpaste.history", qos: .utility)
    private let fileURL: URL
    private let maximumCount = 200

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("JevPaste", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        fileURL = directory.appendingPathComponent("history.enc")
        load()
    }

    func add(text: String, sourceApp: String) {
        guard let text = SensitiveDataFilter.sanitizedCandidate(text) else { return }
        clips.removeAll { $0.text == text }
        clips.insert(Clip(id: UUID(), text: text, sourceApp: sourceApp, createdAt: Date()), at: 0)
        if clips.count > maximumCount { clips.removeLast(clips.count - maximumCount) }
        persist()
        onChange?()
    }

    func clear() {
        clips.removeAll()
        persist()
        onChange?()
    }

    func latestCopy() -> Clip? {
        clips.first
    }

    private func load() {
        guard let sealed = try? Data(contentsOf: fileURL),
              let keyData = try? KeychainStore.shared.historyKey(),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plaintext = try? AES.GCM.open(box, using: SymmetricKey(data: keyData)),
              let decoded = try? JSONDecoder().decode([Clip].self, from: plaintext)
        else { return }
        clips = Array(decoded.filter { !SensitiveDataFilter.isSensitiveText($0.text) }.prefix(maximumCount))
    }

    private func persist() {
        let snapshot = clips
        let destination = fileURL
        queue.async {
            guard let encoded = try? JSONEncoder().encode(snapshot),
                  let keyData = try? KeychainStore.shared.historyKey(),
                  let combined = try? AES.GCM.seal(encoded, using: SymmetricKey(data: keyData)).combined
            else { return }
            do {
                try combined.write(to: destination, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            } catch {
                // Clipboard contents are deliberately not logged.
            }
        }
    }
}
