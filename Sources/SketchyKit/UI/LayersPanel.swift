import AppKit

/// Layer stack with visibility toggles, blend mode, opacity and the button bar.
final class LayersPanel: FloatingPanel, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let blendPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let opacitySlider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let opacityLabel = NSTextField(labelWithString: "100%")
    private var buttonStrip: [NSButton] = []
    private let blendLabel = NSTextField(labelWithString: "Blend")
    private let opacityTitle = NSTextField(labelWithString: "Opacity")
    private var scroll: NSScrollView!
    /// The palette body. Held directly because `contentView` is swapped for an
    /// empty placeholder while the palette is docked in a rail.
    private var body: NSView!
    private weak var document: Document?
    /// Guards the reload → selection-changed → reload loop.
    private var isReloading = false

    var onAdd: (() -> Void)?
    var onDelete: (() -> Void)?
    var onDuplicate: (() -> Void)?
    var onMerge: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onProperties: (() -> Void)?
    var onChange: (() -> Void)?

    init() {
        super.init(title: "Layers", size: NSSize(width: 262, height: 360))
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 262, height: 360))

        scroll = NSScrollView(frame: NSRect(x: 0, y: 96, width: 262, height: 264))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let col = NSTableColumn(identifier: .init("layer"))
        col.width = 240
        col.resizingMask = .autoresizingMask
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 40
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.doubleAction = #selector(doubleClicked)
        table.target = self
        scroll.documentView = table
        content.addSubview(scroll)

        blendLabel.font = .systemFont(ofSize: 11)
        content.addSubview(blendLabel)

        blendPopup.controlSize = .small
        blendPopup.font = .systemFont(ofSize: 11)
        blendPopup.addItems(withTitles: LayerBlendMode.allCases.map(\.rawValue))
        blendPopup.target = self
        blendPopup.action = #selector(blendChanged)
        content.addSubview(blendPopup)

        opacityTitle.font = .systemFont(ofSize: 11)
        content.addSubview(opacityTitle)

        opacitySlider.controlSize = .small
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        content.addSubview(opacitySlider)

        opacityLabel.font = .systemFont(ofSize: 11)
        content.addSubview(opacityLabel)

        let specs: [(String, Selector, String)] = [
            ("plus.app", #selector(addTapped), "Add a new layer"),
            ("minus.square", #selector(deleteTapped), "Delete this layer"),
            ("plus.square.on.square", #selector(duplicateTapped), "Duplicate this layer"),
            ("square.stack.3d.down.right", #selector(mergeTapped), "Merge layer down"),
            ("arrow.up.square", #selector(upTapped), "Move layer up"),
            ("arrow.down.square", #selector(downTapped), "Move layer down"),
            ("wrench.and.screwdriver", #selector(propertiesTapped), "Layer properties")
        ]
        for spec in specs {
            let b = NSButton(image: NSImage.symbol(spec.0, spec.2),
                             target: self, action: spec.1)
            b.isBordered = false
            b.toolTip = spec.2
            content.addSubview(b)
            buttonStrip.append(b)
        }
        content.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(contentResized),
                                               name: NSView.frameDidChangeNotification, object: content)

        body = content
        contentView = content
        contentResized()
    }

    /// Lays the panel out for its current width: the button strip wraps, and the
    /// blend/opacity rows stack their labels once there is no room beside them.
    @objc private func contentResized() {
        guard let content = body else { return }
        let w = content.bounds.width
        let margin: CGFloat = 12
        let spacing: CGFloat = 34
        let perRow = max(1, Int((w - margin * 2 + 6) / spacing))
        let rows = Int(ceil(Double(buttonStrip.count) / Double(perRow)))

        for (i, b) in buttonStrip.enumerated() {
            let row = rows - 1 - (i / perRow), col = i % perRow
            b.frame = NSRect(x: margin + CGFloat(col) * spacing,
                             y: 6 + CGFloat(row) * 26, width: 28, height: 24)
        }

        var y = 6 + CGFloat(rows) * 26 + 4
        let stacked = w < 200
        let labelWidth: CGFloat = 56
        let controlX = stacked ? margin : margin + labelWidth + 6
        let controlWidth = max(40, w - controlX - margin - (stacked ? 0 : 46))

        if stacked {
            opacityTitle.frame = NSRect(x: margin, y: y + 20, width: labelWidth, height: 16)
            opacitySlider.frame = NSRect(x: margin, y: y, width: max(40, w - margin * 2 - 44), height: 20)
            opacityLabel.frame = NSRect(x: w - margin - 40, y: y + 2, width: 40, height: 16)
            y += 40
            blendLabel.frame = NSRect(x: margin, y: y + 22, width: labelWidth, height: 16)
            blendPopup.frame = NSRect(x: margin, y: y, width: max(60, w - margin * 2), height: 22)
            y += 44
        } else {
            opacityTitle.frame = NSRect(x: margin, y: y + 2, width: labelWidth, height: 16)
            opacitySlider.frame = NSRect(x: controlX, y: y, width: controlWidth, height: 20)
            opacityLabel.frame = NSRect(x: w - margin - 42, y: y + 2, width: 42, height: 16)
            y += 26
            blendLabel.frame = NSRect(x: margin, y: y + 3, width: labelWidth, height: 16)
            blendPopup.frame = NSRect(x: controlX, y: y, width: max(60, w - controlX - margin), height: 22)
            y += 30
        }

        scroll.frame = NSRect(x: 0, y: y, width: w, height: max(40, content.bounds.height - y))
    }

    func attach(_ doc: Document) {
        document = doc
        doc.onStructureChange = { [weak self] in self?.reload() }
        reload()
    }

    func reload() {
        isReloading = true
        defer { isReloading = false }
        table.reloadData()
        guard let doc = document else { return }
        // Row 0 is the top-most layer, so the table is the reverse of the model.
        let row = doc.layers.count - 1 - doc.selectedLayerIndex
        if doc.layers.indices.contains(doc.selectedLayerIndex) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        if let l = doc.selectedLayer {
            blendPopup.selectItem(withTitle: l.blendMode.rawValue)
            opacitySlider.doubleValue = Double(l.opacity * 100)
            opacityLabel.stringValue = "\(Int(l.opacity * 100))%"
        }
    }

    private func modelIndex(forRow row: Int) -> Int {
        (document?.layers.count ?? 1) - 1 - row
    }

    // MARK: - Actions

    @objc private func blendChanged() {
        guard let doc = document, let l = doc.selectedLayer,
              let mode = LayerBlendMode(rawValue: blendPopup.titleOfSelectedItem ?? "") else { return }
        l.blendMode = mode
        doc.commit("Layer Blend Mode")
        onChange?()
    }

    @objc private func opacityChanged() {
        guard let doc = document, let l = doc.selectedLayer else { return }
        l.opacity = CGFloat(opacitySlider.doubleValue / 100)
        opacityLabel.stringValue = "\(Int(opacitySlider.doubleValue))%"
        doc.onChange?()
        if NSApp.currentEvent?.type == .leftMouseUp { doc.commit("Layer Opacity") }
        onChange?()
    }

    @objc private func addTapped() { onAdd?() }
    @objc private func deleteTapped() { onDelete?() }
    @objc private func duplicateTapped() { onDuplicate?() }
    @objc private func mergeTapped() { onMerge?() }
    @objc private func upTapped() { onMoveUp?() }
    @objc private func downTapped() { onMoveDown?() }
    @objc private func propertiesTapped() { onProperties?() }
    @objc private func doubleClicked() { onProperties?() }

    @objc fileprivate func visibilityToggled(_ sender: NSButton) {
        guard let doc = document else { return }
        let index = modelIndex(forRow: sender.tag)
        guard doc.layers.indices.contains(index) else { return }
        doc.layers[index].isVisible = (sender.state == .on)
        doc.onChange?()
        onChange?()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { document?.layers.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let doc = document else { return nil }
        let layer = doc.layers[modelIndex(forRow: row)]
        let cell = LayerCellView()
        cell.thumb.image = layer.thumbnail(size: NSSize(width: 34, height: 34))
        cell.label.stringValue = layer.name
        cell.visibility.state = layer.isVisible ? .on : .off
        cell.visibility.tag = row
        cell.visibility.target = self
        cell.visibility.action = #selector(visibilityToggled(_:))
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloading, let doc = document, table.selectedRow >= 0 else { return }
        doc.selectedLayerIndex = modelIndex(forRow: table.selectedRow)
        if let l = doc.selectedLayer {
            blendPopup.selectItem(withTitle: l.blendMode.rawValue)
            opacitySlider.doubleValue = Double(l.opacity * 100)
            opacityLabel.stringValue = "\(Int(l.opacity * 100))%"
        }
        onChange?()
    }
}

/// One row in the Layers table: thumbnail, name, visibility checkbox.
final class LayerCellView: NSTableCellView {
    let thumb = NSImageView()
    let label = NSTextField(labelWithString: "")
    let visibility = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        thumb.frame = NSRect(x: 4, y: 3, width: 34, height: 34)
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.borderWidth = 1
        thumb.layer?.borderColor = NSColor(white: 0.35, alpha: 1).cgColor
        addSubview(thumb)

        label.frame = NSRect(x: 46, y: 11, width: 160, height: 18)
        label.font = .systemFont(ofSize: 12)
        label.autoresizingMask = [.width]
        addSubview(label)
        textField = label

        visibility.frame = NSRect(x: 212, y: 10, width: 20, height: 20)
        visibility.autoresizingMask = [.minXMargin]
        addSubview(visibility)
    }

    required init?(coder: NSCoder) { fatalError() }
}
