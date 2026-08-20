import AppKit

/// Where a palette currently lives.
enum DockSide: String {
    case floating, left, right
}

/// One palette (Tools, Colors, History, Layers) and the two homes it can have:
/// its own floating panel, or a slot in one of the window's dock rails.
final class Palette {
    let id: String
    let title: String
    let panel: FloatingPanel
    /// Fallback for content that cannot size itself; nil means "take the slack".
    private let fixedHeight: CGFloat?
    let dockedWidth: CGFloat

    private(set) var side: DockSide = .floating
    private(set) var content: NSView
    private(set) var box: DockedPaletteBox?

    init(id: String, title: String, panel: FloatingPanel, dockedHeight: CGFloat?) {
        self.id = id
        self.title = title
        self.panel = panel
        self.fixedHeight = dockedHeight
        self.dockedWidth = panel.frame.width
        self.content = panel.contentView ?? NSView()
    }

    /// Height the palette wants at a given rail width. Responsive content
    /// recomputes it (the tool grid re-columns, the color wheel shrinks);
    /// nil means the palette stretches to fill the rail.
    func dockedHeight(forWidth width: CGFloat) -> CGFloat? {
        if let responsive = content as? PaletteContent {
            return responsive.preferredHeight(forWidth: width)
        }
        return fixedHeight
    }

    var isVisible: Bool {
        side == .floating ? panel.isVisible : (box?.superview != nil)
    }

    /// Moves the content view out of the panel so a rail can adopt it.
    func detachFromPanel() -> NSView {
        panel.orderOut(nil)
        content.removeFromSuperview()
        panel.contentView = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        return content
    }

    func returnToPanel() {
        content.removeFromSuperview()
        content.frame = NSRect(origin: .zero, size: content.frame.size)
        panel.setContentSize(content.frame.size)
        panel.contentView = content
        box = nil
    }

    func setSide(_ side: DockSide, box: DockedPaletteBox?) {
        self.side = side
        self.box = box
    }
}

/// A docked palette: title bar (drag to tear off, click to collapse) plus content.
final class DockedPaletteBox: NSView {
    static let headerHeight: CGFloat = 22

    let palette: Palette
    private let titleLabel = NSTextField(labelWithString: "")
    private let disclosure = NSButton()
    private let floatButton = NSButton()
    private let contentHolder = NSView()
    private var dragOrigin: NSPoint?

    var isCollapsed = false { didSet { relayout(); onLayoutChange?() } }
    var onTearOff: ((Palette, NSEvent) -> Void)?
    var onLayoutChange: (() -> Void)?

    init(palette: Palette, content: NSView) {
        self.palette = palette
        let width = max(palette.dockedWidth, 200)
        super.init(frame: NSRect(x: 0, y: 0, width: width,
                                 height: (palette.dockedHeight(forWidth: width) ?? 260)
                                     + DockedPaletteBox.headerHeight))
        wantsLayer = true
        clipsToBounds = true

        titleLabel.stringValue = palette.title
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        addSubview(titleLabel)

        disclosure.bezelStyle = .inline
        disclosure.isBordered = false
        disclosure.target = self
        disclosure.action = #selector(toggleCollapsed)
        disclosure.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Collapse")
        addSubview(disclosure)

        floatButton.bezelStyle = .inline
        floatButton.isBordered = false
        floatButton.target = self
        floatButton.action = #selector(floatIt)
        floatButton.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Float")
        floatButton.toolTip = "Float this palette"
        addSubview(floatButton)

        contentHolder.addSubview(content)
        addSubview(contentHolder)
        relayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    var contentView: NSView? { contentHolder.subviews.first }

    /// Height this box wants: header only when collapsed, otherwise header + content.
    func fittingHeight(available: CGFloat, width: CGFloat? = nil) -> CGFloat {
        if isCollapsed { return DockedPaletteBox.headerHeight }
        if let h = palette.dockedHeight(forWidth: width ?? bounds.width) {
            return h + DockedPaletteBox.headerHeight
        }
        return max(120, available)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        relayout()
    }

    private func relayout() {
        let header = DockedPaletteBox.headerHeight
        titleLabel.frame = NSRect(x: 24, y: bounds.height - header + 3, width: bounds.width - 70, height: 15)
        disclosure.frame = NSRect(x: 4, y: bounds.height - header + 2, width: 18, height: 18)
        floatButton.frame = NSRect(x: bounds.width - 24, y: bounds.height - header + 2, width: 18, height: 18)
        disclosure.image = NSImage(systemSymbolName: isCollapsed ? "chevron.right" : "chevron.down",
                                   accessibilityDescription: "Collapse")
        contentHolder.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - header))
        contentHolder.isHidden = isCollapsed
        if let content = contentView {
            // Every palette body lays itself out for the width it is given.
            content.autoresizingMask = [.width, .height]
            content.frame = contentHolder.bounds
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 0, y: bounds.height - DockedPaletteBox.headerHeight + 0.5))
        line.line(to: NSPoint(x: bounds.width, y: bounds.height - DockedPaletteBox.headerHeight + 0.5))
        line.stroke()
    }

    @objc private func toggleCollapsed() { isCollapsed.toggle() }
    @objc private func floatIt() { onTearOff?(palette, NSApp.currentEvent ?? NSEvent()) }

    private func isInHeader(_ point: NSPoint) -> Bool {
        point.y >= bounds.height - DockedPaletteBox.headerHeight
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragOrigin = isInHeader(p) ? event.locationInWindow : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let moved = hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y)
        guard moved > 6 else { return }
        dragOrigin = nil
        onTearOff?(palette, event)
    }
}

/// A vertical column of docked palettes along one side of the canvas.
final class DockRail: NSView {
    let side: DockSide
    private(set) var boxes: [DockedPaletteBox] = []
    /// Highlight shown while a palette is dragged over this rail.
    private(set) var isTargeted = false

    /// Rails go as narrow as a single column of tool buttons.
    var width: CGFloat = 264 { didSet { width = min(520, max(56, width)) } }
    var onLayoutChange: (() -> Void)?
    /// Called when the user finishes dragging the rail's edge.
    var onWidthCommitted: (() -> Void)?
    /// Width of the grab strip along the rail's inner edge.
    private let grabWidth: CGFloat = 6
    private var isResizing = false
    /// Set once the user drags the edge, so automatic sizing stops fighting them.
    private(set) var hasCustomWidth = false

    init(side: DockSide) {
        self.side = side
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    var isEmpty: Bool { boxes.isEmpty }

    func add(_ box: DockedPaletteBox, at index: Int? = nil) {
        let i = min(index ?? boxes.count, boxes.count)
        boxes.insert(box, at: i)
        addSubview(box)
        box.onLayoutChange = { [weak self] in self?.layoutBoxes() }
        layoutBoxes()
        onLayoutChange?()
    }

    func remove(_ box: DockedPaletteBox) {
        boxes.removeAll { $0 === box }
        box.removeFromSuperview()
        layoutBoxes()
        onLayoutChange?()
    }

    func adoptWidth(_ newWidth: CGFloat, custom: Bool) {
        width = newWidth
        hasCustomWidth = custom
    }

    func setTargeted(_ targeted: Bool) {
        guard isTargeted != targeted else { return }
        isTargeted = targeted
        needsDisplay = true
    }

    /// Self-sizing boxes keep their preferred height at the current rail width;
    /// stretchy ones (History, Layers) share whatever is left over.
    func layoutBoxes() {
        guard !boxes.isEmpty else { return }
        let w = bounds.width
        func stretches(_ box: DockedPaletteBox) -> Bool {
            !box.isCollapsed && box.palette.dockedHeight(forWidth: w) == nil
        }
        let flexible = boxes.filter(stretches)
        let usedByFixed = boxes.filter { !stretches($0) }
            .reduce(0) { $0 + $1.fittingHeight(available: 0, width: w) }
        let slack = max(0, bounds.height - usedByFixed)
        let each = flexible.isEmpty ? 0 : slack / CGFloat(flexible.count)

        var y = bounds.height
        for box in boxes {
            let h = stretches(box) ? max(120, each) : box.fittingHeight(available: 0, width: w)
            y -= h
            box.frame = NSRect(x: 0, y: y, width: w, height: h)
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutBoxes()
    }

    // MARK: - Resizing the rail

    private var grabRect: NSRect {
        side == .left
            ? NSRect(x: bounds.maxX - grabWidth, y: 0, width: grabWidth, height: bounds.height)
            : NSRect(x: 0, y: 0, width: grabWidth, height: bounds.height)
    }

    /// The grab strip has to win over the palette boxes stacked on top of it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if !isEmpty && grabRect.contains(local) { return self }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        guard !isEmpty else { return }
        addCursorRect(grabRect, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        isResizing = grabRect.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isResizing, let parent = superview else { return }
        let p = parent.convert(event.locationInWindow, from: nil)
        width = side == .left ? p.x : parent.bounds.width - p.x
        hasCustomWidth = true
        onLayoutChange?()
    }

    override func mouseUp(with event: NSEvent) {
        if isResizing { onWidthCommitted?() }
        isResizing = false
        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let x = side == .left ? bounds.maxX - 0.5 : 0.5
        let line = NSBezierPath()
        line.move(to: NSPoint(x: x, y: 0))
        line.line(to: NSPoint(x: x, y: bounds.height))
        line.stroke()

        if isTargeted {
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
            bounds.fill()
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
            outline.lineWidth = 3
            outline.stroke()
        }
    }
}
