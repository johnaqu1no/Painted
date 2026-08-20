import AppKit

/// Keeps the palettes in sync between their floating panels and the window's
/// dock rails, including drag-to-dock and remembering the layout between runs.
final class DockManager {
    /// The document window the palettes currently belong to. With tabbed
    /// windows this follows whichever tab is active.
    private weak var window: NSWindow?
    private(set) var palettes: [Palette] = []
    private(set) var leftRail = DockRail(side: .left)
    private(set) var rightRail = DockRail(side: .right)

    /// Fired whenever the window needs to re-lay-out around the rails.
    var onLayoutChange: (() -> Void)?

    /// Set while palettes are being moved between windows, so rail widths are
    /// carried across instead of being recalculated from the first palette.
    private var isRebindingRails = false
    private var dragTimer: Timer?
    private var draggingPalette: Palette?
    private var observers: [NSObjectProtocol] = []

    private let defaultsKey = "SketchyPaletteLayout"

    init(window: NSWindow? = nil) {
        self.window = window
        leftRail.onLayoutChange = { [weak self] in self?.onLayoutChange?() }
        rightRail.onLayoutChange = { [weak self] in self?.onLayoutChange?() }
        leftRail.onWidthCommitted = { [weak self] in self?.saveLayout() }
        rightRail.onWidthCommitted = { [weak self] in self?.saveLayout() }
    }

    /// Points the manager at another window's rails, carrying every docked
    /// palette across. Called when a document tab becomes active.
    func useRails(left: DockRail, right: DockRail, in window: NSWindow) {
        guard left !== leftRail || right !== rightRail else {
            self.window = window
            return
        }
        let previous: [(Palette, DockSide, Bool)] = palettes.compactMap { palette in
            guard palette.side != .floating else { return nil }
            return (palette, palette.side, palette.box?.isCollapsed ?? false)
        }
        for (palette, _, _) in previous {
            if let box = palette.box, let rail = rail(for: palette.side) {
                box.contentView?.removeFromSuperview()
                rail.remove(box)
            }
            palette.setSide(.floating, box: nil)
        }

        let carriedLeft = (leftRail.width, leftRail.hasCustomWidth)
        let carriedRight = (rightRail.width, rightRail.hasCustomWidth)
        leftRail = left
        rightRail = right
        self.window = window
        leftRail.onLayoutChange = { [weak self] in self?.onLayoutChange?() }
        rightRail.onLayoutChange = { [weak self] in self?.onLayoutChange?() }
        leftRail.onWidthCommitted = { [weak self] in self?.saveLayout() }
        rightRail.onWidthCommitted = { [weak self] in self?.saveLayout() }

        isRebindingRails = true
        for (palette, side, collapsed) in previous {
            dock(palette, to: side)
            if collapsed { palette.box?.isCollapsed = true }
        }
        isRebindingRails = false
        left.adoptWidth(carriedLeft.0, custom: carriedLeft.1)
        right.adoptWidth(carriedRight.0, custom: carriedRight.1)
        onLayoutChange?()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        dragTimer?.invalidate()
    }

    func register(_ palette: Palette) {
        palettes.append(palette)
        palette.panel.setFrameAutosaveName("Sketchy.palette.\(palette.id)")
        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: palette.panel, queue: .main
        ) { [weak self] _ in
            self?.panelMoved(palette)
        }
        observers.append(token)
    }

    func palette(id: String) -> Palette? { palettes.first { $0.id == id } }

    func rail(for side: DockSide) -> DockRail? {
        switch side {
        case .left:  return leftRail
        case .right: return rightRail
        case .floating: return nil
        }
    }

    // MARK: - Docking

    func dock(_ palette: Palette, to side: DockSide, at index: Int? = nil) {
        guard let target = rail(for: side) else { float(palette); return }
        if let existing = palette.box, let currentRail = rail(for: palette.side) {
            currentRail.remove(existing)
        }
        let content = palette.side == .floating ? palette.detachFromPanel() : (palette.box?.contentView ?? palette.content)
        content.removeFromSuperview()
        let box = DockedPaletteBox(palette: palette, content: content)
        box.onTearOff = { [weak self] p, event in self?.tearOff(p, with: event) }
        target.add(box, at: index)
        palette.setSide(side, box: box)
        if !isRebindingRails && !target.hasCustomWidth {
            // Fit the widest palette in the rail, so a narrow one (Tools) does
            // not squeeze a wide one (Colors).
            let needed = target.boxes.map { $0.palette.dockedWidth + 8 }.max() ?? 264
            target.width = min(320, needed)
        }
        onLayoutChange?()
        saveLayout()
    }

    func float(_ palette: Palette, at screenOrigin: NSPoint? = nil) {
        if palette.side != .floating, let rail = rail(for: palette.side), let box = palette.box {
            box.contentView?.removeFromSuperview()
            rail.remove(box)
        }
        palette.returnToPanel()
        palette.setSide(.floating, box: nil)
        if let origin = screenOrigin {
            palette.panel.setFrameTopLeftPoint(origin)
        }
        palette.panel.orderFront(nil)
        onLayoutChange?()
        saveLayout()
    }

    /// Dragging a docked palette's header pulls it back out into its panel and
    /// hands the drag straight over to the window server.
    private func tearOff(_ palette: Palette, with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        float(palette, at: NSPoint(x: mouse.x - palette.panel.frame.width / 2, y: mouse.y + 10))
        if event.type == .leftMouseDragged || event.type == .leftMouseDown {
            palette.panel.performDrag(with: event)
        }
    }

    func toggle(_ palette: Palette) {
        switch palette.side {
        case .floating:
            palette.panel.toggle()
        case .left, .right:
            // Docked palettes collapse to their header rather than disappearing.
            palette.box?.isCollapsed.toggle()
            onLayoutChange?()
        }
        saveLayout()
    }

    // MARK: - Drag to dock

    /// Screen rect of the strip that docks to a given side.
    private func hotZone(for side: DockSide) -> NSRect {
        guard let window, let content = window.contentView else { return .zero }
        let inWindow = content.convert(content.bounds, to: nil)
        let screen = window.convertToScreen(inWindow)
        let strip = max(140, rail(for: side)?.width ?? 140)
        return side == .left
            ? NSRect(x: screen.minX, y: screen.minY, width: strip, height: screen.height)
            : NSRect(x: screen.maxX - strip, y: screen.minY, width: strip, height: screen.height)
    }

    private func zoneUnderMouse() -> DockSide? {
        let mouse = NSEvent.mouseLocation
        if hotZone(for: .left).contains(mouse) { return .left }
        if hotZone(for: .right).contains(mouse) { return .right }
        return nil
    }

    private func panelMoved(_ palette: Palette) {
        guard palette.side == .floating else { return }
        draggingPalette = palette
        highlight(zoneUnderMouse())

        // Window dragging runs its own event loop, so poll for the mouse-up
        // instead of waiting for an event we would never see.
        dragTimer?.invalidate()
        dragTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if NSEvent.pressedMouseButtons == 0 {
                timer.invalidate()
                self.dragTimer = nil
                self.finishDrag()
            } else {
                self.highlight(self.zoneUnderMouse())
            }
        }
        RunLoop.main.add(dragTimer!, forMode: .common)
    }

    private func finishDrag() {
        defer { draggingPalette = nil; highlight(nil) }
        guard let palette = draggingPalette, let side = zoneUnderMouse() else { return }
        dock(palette, to: side)
    }

    private func highlight(_ side: DockSide?) {
        leftRail.setTargeted(side == .left)
        rightRail.setTargeted(side == .right)
        // Empty rails are zero-width, so widen them while they are a drop target.
        onLayoutChange?()
    }

    // MARK: - Persistence

    func saveLayout() {
        var state: [String: String] = [:]
        for p in palettes {
            state[p.id] = p.side.rawValue + (p.box?.isCollapsed == true ? "|collapsed" : "")
        }
        state["__railWidths"] = "\(Int(leftRail.width)):\(Int(rightRail.width))"
        UserDefaults.standard.set(state, forKey: defaultsKey)
    }

    func restoreLayout() {
        guard let state = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] else { return }
        if let widths = state["__railWidths"]?.split(separator: ":"), widths.count == 2 {
            leftRail.adoptWidth(CGFloat(Double(widths[0]) ?? 264), custom: true)
            rightRail.adoptWidth(CGFloat(Double(widths[1]) ?? 264), custom: true)
        }
        for p in palettes {
            guard let raw = state[p.id] else { continue }
            let parts = raw.split(separator: "|")
            guard let side = DockSide(rawValue: String(parts[0])) else { continue }
            if side == .floating {
                float(p)
            } else {
                dock(p, to: side)
                if parts.count > 1 { p.box?.isCollapsed = true }
            }
        }
        onLayoutChange?()
    }

    func resetLayout() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        for p in palettes { float(p) }
        onLayoutChange?()
    }
}
