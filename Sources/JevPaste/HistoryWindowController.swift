import AppKit

final class HistoryPanel: NSPanel {
    var onHide: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
        onHide?()
    }

    override func close() {
        super.close()
        onHide?()
    }
}

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onVisibilityChanged: (() -> Void)?

    private let store: EncryptedHistoryStore
    private let table = NSTableView()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    init(store: EncryptedHistoryStore) {
        self.store = store
        let panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 430),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "JevPaste 履歴"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.onHide = { [weak self] in self?.onVisibilityChanged?() }
        buildUI(in: panel)
    }

    required init?(coder: NSCoder) { nil }

    var isVisible: Bool { window?.isVisible == true }

    func toggle() {
        if isVisible {
            window?.orderOut(nil)
        } else {
            reload()
            window?.center()
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        onVisibilityChanged?()
    }

    func reload() {
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { store.clips.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < store.clips.count else { return nil }
        let clip = store.clips[row]
        let identifier = NSUserInterfaceItemIdentifier("ClipCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
            let view = NSTableCellView()
            view.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 2
            view.textField = label
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            return view
        }()
        cell.textField?.stringValue = "\(clip.text.replacingOccurrences(of: "\n", with: "  "))   — \(clip.sourceApp) · \(dateFormatter.string(from: clip.createdAt))"
        return cell
    }

    @objc private func copySelected() {
        let row = table.selectedRow
        guard row >= 0, row < store.clips.count else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.clips[row].text, forType: .string)
    }

    @objc private func closePanel() {
        window?.orderOut(nil)
        onVisibilityChanged?()
    }

    private func buildUI(in panel: NSPanel) {
        guard let content = panel.contentView else { return }
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("History"))
        column.title = "最近のテキスト（ダブルクリックでコピー）"
        table.addTableColumn(column)
        table.headerView = NSTableHeaderView()
        table.rowHeight = 42
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(copySelected)
        scroll.documentView = table

        let close = NSButton(title: "閉じる", target: self, action: #selector(closePanel))
        close.keyEquivalent = "\u{1b}"
        close.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scroll)
        content.addSubview(close)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -12),
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            close.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }
}
