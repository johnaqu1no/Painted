import AppKit

/// Lists every undo step; clicking a row time-travels to it.
final class HistoryPanel: FloatingPanel, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private weak var document: Document?
    var onJump: ((Int) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?

    init() {
        super.init(title: "History", size: NSSize(width: 250, height: 340))
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 340))

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 34, width: 250, height: 306))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let col = NSTableColumn(identifier: .init("step"))
        col.width = 230
        col.resizingMask = .autoresizingMask
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.addTableColumn(col)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.rowHeight = 22
        table.selectionHighlightStyle = .regular
        table.target = self
        table.action = #selector(rowClicked)
        scroll.documentView = table
        content.addSubview(scroll)

        let undoBtn = NSButton(image: NSImage.symbol("arrow.uturn.backward", "Undo"),
                               target: self, action: #selector(undoTapped))
        undoBtn.frame = NSRect(x: 10, y: 6, width: 26, height: 22)
        undoBtn.isBordered = false
        undoBtn.toolTip = "Undo"
        let redoBtn = NSButton(image: NSImage.symbol("arrow.uturn.forward", "Redo"),
                               target: self, action: #selector(redoTapped))
        redoBtn.frame = NSRect(x: 44, y: 6, width: 26, height: 22)
        redoBtn.isBordered = false
        redoBtn.toolTip = "Redo"
        content.addSubview(undoBtn)
        content.addSubview(redoBtn)

        contentView = content
    }

    func attach(_ doc: Document) {
        document = doc
        doc.history.onChange = { [weak self] in self?.reload() }
        reload()
    }

    func reload() {
        table.reloadData()
        if let cursor = document?.history.cursor, cursor >= 0 {
            table.selectRowIndexes(IndexSet(integer: cursor), byExtendingSelection: false)
            table.scrollRowToVisible(cursor)
        }
    }

    @objc private func rowClicked() {
        guard table.clickedRow >= 0 else { return }
        onJump?(table.clickedRow)
    }

    @objc private func undoTapped() { onUndo?() }
    @objc private func redoTapped() { onRedo?() }

    func numberOfRows(in tableView: NSTableView) -> Int {
        document?.history.entries.count ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.frame = NSRect(x: 6, y: 2, width: 210, height: 17)
            tf.autoresizingMask = [.width]
            tf.font = .systemFont(ofSize: 12)
            c.addSubview(tf)
            c.textField = tf
            return c
        }()
        guard let entry = document?.history.entries[row] else { return cell }
        cell.textField?.stringValue = entry.title
        let isFuture = (document?.history.cursor ?? 0) < row
        cell.textField?.textColor = isFuture ? .disabledControlTextColor : .labelColor
        return cell
    }
}
