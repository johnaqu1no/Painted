import AppKit

/// A palette body that lays itself out for whatever width it is given.
/// `preferredHeight` returning nil means "stretch to fill the dock rail".
protocol PaletteContent: NSView {
    func preferredHeight(forWidth width: CGFloat) -> CGFloat?
}

/// Content view for the Tools palette: a flow grid that re-columns as it narrows.
final class ToolsPaletteView: NSView, PaletteContent {
    private var buttons: [ToolID: IconButton] = [:]
    private let cell = NSSize(width: 34, height: 34)
    /// Shortcuts are shown in the tooltips, and can change while running.
    var shortcuts: ToolShortcuts? { didSet { refreshTooltips() } }
    private let inset: CGFloat = 8
    var onSelect: ((ToolID) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for (i, tool) in ToolID.paletteOrder.enumerated() {
            let b = IconButton(symbol: tool.symbol, tooltip: tool.title,
                               target: self, action: #selector(pick(_:)))
            b.tag = i
            buttons[tool] = b
            addSubview(b)
        }
        layoutGrid()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func columns(forWidth width: CGFloat) -> Int {
        max(1, Int((width - inset * 2) / cell.width))
    }

    func preferredHeight(forWidth width: CGFloat) -> CGFloat? {
        let cols = columns(forWidth: width)
        let rows = Int(ceil(Double(ToolID.paletteOrder.count) / Double(cols)))
        return CGFloat(rows) * cell.height + inset * 2
    }

    /// Width that fits a given number of columns, for the floating panel.
    func width(forColumns cols: Int) -> CGFloat {
        CGFloat(cols) * cell.width + inset * 2
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutGrid()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutGrid()
    }

    private func layoutGrid() {
        let cols = columns(forWidth: bounds.width)
        let gridWidth = CGFloat(cols) * cell.width
        let left = ((bounds.width - gridWidth) / 2).rounded()
        for (i, tool) in ToolID.paletteOrder.enumerated() {
            guard let b = buttons[tool] else { continue }
            let col = i % cols, row = i / cols
            b.frame = NSRect(x: left + CGFloat(col) * cell.width,
                             y: bounds.height - inset - CGFloat(row + 1) * cell.height,
                             width: cell.width - 4, height: cell.height - 4)
        }
    }

    @objc private func pick(_ sender: IconButton) {
        let tool = ToolID.paletteOrder[sender.tag]
        select(tool)
        onSelect?(tool)
    }

    func select(_ tool: ToolID) {
        for (id, b) in buttons { b.isSelectedTool = (id == tool) }
    }

    /// "Paintbrush (B)", or just the name when the tool has no key.
    func refreshTooltips() {
        for (tool, button) in buttons {
            if let key = shortcuts?.key(for: tool)?.uppercased() {
                button.toolTip = "\(tool.title) (\(key))"
            } else {
                button.toolTip = tool.title
            }
        }
    }
}

/// Content view for the Colors palette: swatches, wheel, value slider and the
/// palette strip, all sized from the available width.
final class ColorsPaletteView: NSView, PaletteContent {
    let primarySwatch = SwatchView()
    let secondarySwatch = SwatchView()
    let wheel = ColorWheelView()
    let valueSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    let paletteView = PaletteView()
    let swapButton = NSButton()
    let resetButton = NSButton()
    let moreButton = NSButton(title: "More >>", target: nil, action: nil)
    let addSwatchButton = NSButton()
    let presetsButton = NSPopUpButton(frame: .zero, pullsDown: true)

    /// Numeric entry: hex, then R/G/B/A and H/S/V in Paint.NET's units.
    let hexField = NSTextField(string: "000000")
    let redField = NSTextField(string: "0")
    let greenField = NSTextField(string: "0")
    let blueField = NSTextField(string: "0")
    let alphaField = NSTextField(string: "255")
    let hueField = NSTextField(string: "0")
    let saturationField = NSTextField(string: "0")
    let valueField = NSTextField(string: "0")

    var rgbaFields: [NSTextField] { [redField, greenField, blueField, alphaField] }
    var hsvFields: [NSTextField] { [hueField, saturationField, valueField] }
    private var fieldLabels: [NSTextField] = []

    private let margin: CGFloat = 12
    private let swatchRow: CGFloat = 52
    private let sliderRow: CGFloat = 24
    private let stripRow: CGFloat = 44
    private let buttonRow: CGFloat = 26
    private let fieldHeight: CGFloat = 20
    private let fieldGap: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        [secondarySwatch, primarySwatch, swapButton, resetButton, moreButton,
         wheel, valueSlider, addSwatchButton, presetsButton, paletteView].forEach(addSubview)

        swapButton.isBordered = false
        swapButton.image = NSImage(systemSymbolName: "arrow.2.squarepath", accessibilityDescription: "Swap colors")
        swapButton.toolTip = "Swap primary and secondary colors"

        resetButton.isBordered = false
        resetButton.image = NSImage(systemSymbolName: "square.filled.on.square", accessibilityDescription: "Reset")
        resetButton.toolTip = "Reset to black / white"

        moreButton.bezelStyle = .rounded
        moreButton.controlSize = .small

        valueSlider.controlSize = .small

        addSwatchButton.isBordered = false
        addSwatchButton.image = NSImage(systemSymbolName: "plus.square", accessibilityDescription: "Add swatch")
        addSwatchButton.toolTip = "Add the primary color to the palette"

        presetsButton.isBordered = false
        presetsButton.addItem(withTitle: "")
        presetsButton.item(at: 0)?.image = NSImage(systemSymbolName: "paintpalette",
                                                   accessibilityDescription: "Palettes")

        hexField.placeholderString = "RRGGBB"
        hexField.toolTip = "Hex value, with or without a leading # (RGB, RRGGBB or RRGGBBAA)"
        addSubview(hexField)
        for (field, name) in zip(rgbaFields + hsvFields,
                                 ["Red", "Green", "Blue", "Alpha", "Hue", "Saturation", "Value"]) {
            field.alignment = .right
            field.toolTip = name
            addSubview(field)
        }
        for title in ["Hex", "R", "G", "B", "A", "H", "S", "V"] {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 10)
            label.textColor = .secondaryLabelColor
            fieldLabels.append(label)
            addSubview(label)
        }
        for field in [hexField] + rgbaFields + hsvFields {
            field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            field.controlSize = .small
        }
    }

    /// The numeric fields wrap into as many rows as the width allows.
    private func fieldRows(forWidth width: CGFloat) -> (perRow: Int, rows: Int) {
        let perRow = max(2, min(4, Int((width - margin * 2) / 52)))
        let rgbaRows = Int(ceil(4.0 / Double(perRow)))
        let hsvRows = Int(ceil(3.0 / Double(perRow)))
        return (perRow, 1 + rgbaRows + hsvRows)
    }

    private func fieldsHeight(forWidth width: CGFloat) -> CGFloat {
        CGFloat(fieldRows(forWidth: width).rows) * (fieldHeight + fieldGap + 12)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The wheel is square and takes whatever width is left after the margins.
    private func wheelSide(forWidth width: CGFloat) -> CGFloat {
        min(max(70, width - margin * 2), 210)
    }

    func preferredHeight(forWidth width: CGFloat) -> CGFloat? {
        let rows: CGFloat = swatchRow + sliderRow + buttonRow + stripRow
        let content: CGFloat = wheelSide(forWidth: width) + fieldsHeight(forWidth: width)
        return rows + content + margin * 2
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutContents()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContents()
    }

    /// Hex on its own row, then R/G/B/A and H/S/V wrapped to fit the width.
    private func layoutFields(top: CGFloat, width w: CGFloat) {
        let (perRow, _) = fieldRows(forWidth: w)
        let cellHeight = fieldHeight + fieldGap + 12
        var y = top - cellHeight

        let hexLabel = fieldLabels[0]
        hexLabel.frame = NSRect(x: margin, y: y + fieldHeight + 2, width: 40, height: 12)
        hexField.frame = NSRect(x: margin, y: y, width: max(60, w - margin * 2), height: fieldHeight)

        var index = 0
        for group in [rgbaFields, hsvFields] {
            var placed = 0
            while placed < group.count {
                y -= cellHeight
                let inRow = min(perRow, group.count - placed)
                let cellWidth = (w - margin * 2 - CGFloat(inRow - 1) * fieldGap) / CGFloat(inRow)
                for column in 0..<inRow {
                    let x = margin + CGFloat(column) * (cellWidth + fieldGap)
                    let label = fieldLabels[1 + index]
                    label.frame = NSRect(x: x + 2, y: y + fieldHeight + 2, width: cellWidth, height: 12)
                    group[placed + column].frame = NSRect(x: x, y: y, width: cellWidth, height: fieldHeight)
                    index += 1
                }
                placed += inRow
            }
        }
    }

    private func layoutContents() {
        let w = bounds.width
        let narrow = w < 150
        var y = bounds.height - margin

        y -= swatchRow
        primarySwatch.frame = NSRect(x: margin, y: y + 18, width: 30, height: 30)
        secondarySwatch.frame = NSRect(x: margin + 16, y: y + 4, width: 26, height: 26)
        swapButton.frame = NSRect(x: margin + 50, y: y + 32, width: 20, height: 18)
        resetButton.frame = NSRect(x: margin + 50, y: y + 12, width: 18, height: 18)
        moreButton.isHidden = narrow
        moreButton.frame = NSRect(x: max(margin + 74, w - margin - 74), y: y + 20, width: 74, height: 22)

        let side = wheelSide(forWidth: w)
        y -= side
        wheel.frame = NSRect(x: ((w - side) / 2).rounded(), y: y, width: side, height: side)

        y -= sliderRow
        valueSlider.frame = NSRect(x: margin, y: y + 2, width: max(40, w - margin * 2), height: 20)

        y -= fieldsHeight(forWidth: w)
        layoutFields(top: y + fieldsHeight(forWidth: w), width: w)

        y -= buttonRow
        addSwatchButton.frame = NSRect(x: margin, y: y, width: 22, height: 22)
        presetsButton.frame = NSRect(x: margin + 26, y: y - 2, width: 46, height: 24)
        presetsButton.isHidden = narrow

        let stripHeight = max(20, min(stripRow, y - margin))
        paletteView.frame = NSRect(x: margin, y: max(margin / 2, y - stripHeight - 4),
                                   width: max(40, w - margin * 2), height: stripHeight)
    }
}
