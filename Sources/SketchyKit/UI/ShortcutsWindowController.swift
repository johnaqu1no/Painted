import AppKit

/// Settings window for rebinding tool shortcuts. One row per tool; type a
/// letter into the field to reassign it, or clear the field to unassign.
final class ShortcutsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let shortcuts: ToolShortcuts
    private let table = NSTableView()
    private let footnote = NSTextField(labelWithString: "")

    init(shortcuts: ToolShortcuts) {
        self.shortcuts = shortcuts
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 470),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Tool Shortcuts"
        window.minSize = NSSize(width: 320, height: 300)
        super.init(window: window)
        window.setFrameAutosaveName("Sketchy.shortcuts")
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 44, width: 380, height: 426))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true

        let toolColumn = NSTableColumn(identifier: .init("tool"))
        toolColumn.title = "Tool"
        toolColumn.width = 250
        let keyColumn = NSTableColumn(identifier: .init("key"))
        keyColumn.title = "Shortcut"
        keyColumn.width = 90
        table.addTableColumn(toolColumn)
        table.addTableColumn(keyColumn)
        table.rowHeight = 26
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        scroll.documentView = table
        content.addSubview(scroll)

        footnote.frame = NSRect(x: 14, y: 14, width: 250, height: 18)
        footnote.autoresizingMask = [.width]
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = .secondaryLabelColor
        footnote.stringValue = "Tools sharing a key cycle."
        content.addSubview(footnote)

        let reset = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        reset.frame = NSRect(x: 380 - 160, y: 10, width: 146, height: 26)
        reset.autoresizingMask = [.minXMargin]
        reset.bezelStyle = .rounded
        content.addSubview(reset)
    }

    @objc private func restoreDefaults() {
        shortcuts.reset()
        table.reloadData()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { ToolID.paletteOrder.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let tool = ToolID.paletteOrder[row]
        let cell = NSTableCellView()

        if tableColumn?.identifier.rawValue == "key" {
            let field = NSTextField(string: shortcuts.key(for: tool)?.uppercased() ?? "")
            field.frame = NSRect(x: 2, y: 2, width: 60, height: 22)
            field.alignment = .center
            field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            field.placeholderString = "—"
            field.tag = row
            field.target = self
            field.action = #selector(keyEdited(_:))
            field.delegate = self
            cell.addSubview(field)
            return cell
        }

        let icon = NSImageView(frame: NSRect(x: 2, y: 4, width: 18, height: 18))
        icon.image = NSImage.symbol(tool.symbol, tool.title)
        icon.contentTintColor = .labelColor
        cell.addSubview(icon)

        let label = NSTextField(labelWithString: tool.title)
        label.frame = NSRect(x: 28, y: 4, width: 210, height: 18)
        label.autoresizingMask = [.width]
        cell.addSubview(label)
        cell.textField = label
        return cell
    }

    @objc private func keyEdited(_ sender: NSTextField) {
        guard ToolID.paletteOrder.indices.contains(sender.tag) else { return }
        let tool = ToolID.paletteOrder[sender.tag]
        shortcuts.setKey(sender.stringValue, for: tool)
        sender.stringValue = shortcuts.key(for: tool)?.uppercased() ?? ""
        table.reloadData()
    }
}

extension ShortcutsWindowController: NSTextFieldDelegate {
    /// Keep the field to a single character while typing.
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field.stringValue.count > 1 else { return }
        field.stringValue = String(field.stringValue.suffix(1)).uppercased()
    }
}
