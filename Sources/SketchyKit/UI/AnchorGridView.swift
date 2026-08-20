import AppKit

/// The nine-cell anchor picker from the resize sheets: the filled cell is where
/// the existing image stays put, and the arrows point at the space being added.
final class AnchorGridView: NSView {
    /// Anchor in unit coordinates, y up: (0, 1) is the top-left cell.
    private(set) var anchor = CGPoint(x: 0.5, y: 0.5)
    var onChange: ((CGPoint) -> Void)?

    private let cell: CGFloat = 26
    private let gap: CGFloat = 2

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setFrameSize(intrinsicContentSize)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: cell * 3 + gap * 2, height: cell * 3 + gap * 2)
    }

    override var isFlipped: Bool { true }

    func setAnchor(_ point: CGPoint) {
        anchor = point
        needsDisplay = true
    }

    /// Column/row in the drawn grid, counting rows from the top.
    private var selectedCell: (column: Int, row: Int) {
        (Int((anchor.x * 2).rounded()), 2 - Int((anchor.y * 2).rounded()))
    }

    private func rect(column: Int, row: Int) -> NSRect {
        NSRect(x: CGFloat(column) * (cell + gap), y: CGFloat(row) * (cell + gap),
               width: cell, height: cell)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let selected = selectedCell

        for row in 0..<3 {
            for column in 0..<3 {
                let box = rect(column: column, row: row)
                let isAnchor = (column == selected.column && row == selected.row)

                if isAnchor {
                    NSColor.controlAccentColor.setFill()
                    NSBezierPath(roundedRect: box.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).fill()
                } else {
                    NSColor(white: 0.35, alpha: 0.35).setFill()
                    NSBezierPath(roundedRect: box.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).fill()
                    drawArrow(from: selected, to: (column, row), in: box, ctx: ctx)
                }
            }
        }
    }

    /// Arrows in the surrounding cells point away from the anchor.
    private func drawArrow(from anchorCell: (column: Int, row: Int),
                           to cell: (Int, Int),
                           in box: NSRect,
                           ctx: CGContext) {
        let dx = cell.0 - anchorCell.column
        let dy = cell.1 - anchorCell.row
        guard dx != 0 || dy != 0 else { return }

        let length = min(box.width, box.height) * 0.28
        let angle = atan2(CGFloat(dy), CGFloat(dx))
        let center = CGPoint(x: box.midX, y: box.midY)
        let tip = CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
        let tail = CGPoint(x: center.x - cos(angle) * length, y: center.y - sin(angle) * length)

        ctx.saveGState()
        ctx.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.move(to: tail)
        ctx.addLine(to: tip)
        for side in [CGFloat.pi * 0.75, -CGFloat.pi * 0.75] {
            ctx.move(to: tip)
            ctx.addLine(to: CGPoint(x: tip.x + cos(angle + side) * length * 0.6,
                                    y: tip.y + sin(angle + side) * length * 0.6))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for row in 0..<3 {
            for column in 0..<3 where rect(column: column, row: row).contains(p) {
                anchor = CGPoint(x: CGFloat(column) / 2, y: CGFloat(2 - row) / 2)
                needsDisplay = true
                onChange?(anchor)
                return
            }
        }
    }
}
