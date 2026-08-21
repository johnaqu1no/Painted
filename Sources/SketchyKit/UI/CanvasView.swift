import AppKit

protocol CanvasViewDelegate: AnyObject {
    func canvasDidChangeZoom(_ view: CanvasView)
    func canvas(_ view: CanvasView, didHoverAt point: CGPoint?)
    func canvasWantsTextEntry(_ view: CanvasView, at point: CGPoint)
    func canvasWantsDelete(_ view: CanvasView)
    func canvasDidChangeMeasurement(_ view: CanvasView)
    func canvas(_ view: CanvasView, didAdjustSetting message: String)
}

/// Draws the composited document and routes pointer input to the tool engine.
/// User space is not flipped, so view coordinates share the document's
/// bottom-left origin once the zoom/centering offset is removed.
final class CanvasView: NSView {
    weak var delegate: CanvasViewDelegate?
    var document: Document
    var engine: ToolEngine
    var settings: ToolSettings

    var zoom: CGFloat = 1.0 {
        didSet {
            zoom = min(32, max(0.05, zoom))
            invalidateIntrinsicContentSize()
            resizeToFit()
            needsDisplay = true
            delegate?.canvasDidChangeZoom(self)
        }
    }

    private var antsPhase: CGFloat = 0
    private var antsTimer: Timer?
    private var cachedComposite: CGImage?
    /// Where the pointer is, in image coordinates, for the brush ring.
    private var hoverPoint: CGPoint? {
        didSet {
            guard settings.tool.hasBrushTip, hoverPoint != oldValue else { return }
            needsDisplay = true
        }
    }
    private var cachedRegion: CGRect = .null
    private var cachedScale: CGFloat = 0
    private var compositeDirty = true
    private var panOrigin: NSPoint?
    /// Fractional wheel movement waiting to add up to a whole step.
    private var wheelSteps: CGFloat = 0
    /// Middle button pans from wherever the pointer is, then hands the canvas
    /// back to whatever tool was in use.

    init(document: Document, engine: ToolEngine, settings: ToolSettings) {
        self.document = document
        self.engine = engine
        self.settings = settings
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        wantsLayer = true
        clipsToBounds = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
        engine.onNeedsDisplay = { [weak self] in self?.refresh() }
        document.onChange = { [weak self] in self?.refresh() }
        // Scrolling changes which slice of the document is on screen.
        NotificationCenter.default.addObserver(self, selector: #selector(viewportMoved),
                                               name: NSView.boundsDidChangeNotification, object: nil)
        startAnts()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { antsTimer?.invalidate() }

    @objc private func viewportMoved(_ note: Notification) {
        guard let clip = note.object as? NSClipView, clip === enclosingScrollView?.contentView else { return }
        needsDisplay = true
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    func refresh() {
        compositeDirty = true
        needsDisplay = true
        delegate?.canvasDidChangeMeasurement(self)
    }

    func replaceDocument(_ doc: Document, engine: ToolEngine) {
        self.document = doc
        self.engine = engine
        engine.onNeedsDisplay = { [weak self] in self?.refresh() }
        doc.onChange = { [weak self] in self?.refresh() }
        resizeToFit()
        refresh()
    }

    // MARK: - Geometry

    var scaledSize: CGSize {
        CGSize(width: document.size.width * zoom, height: document.size.height * zoom)
    }

    /// Where the image sits inside this view, in view coordinates.
    var imageRect: CGRect {
        let s = scaledSize
        let x = max(0, (bounds.width - s.width) / 2).rounded()
        let y = max(0, (bounds.height - s.height) / 2).rounded()
        return CGRect(x: x, y: y, width: s.width, height: s.height)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: scaledSize.width + 40, height: scaledSize.height + 40)
    }

    func resizeToFit() {
        guard let clip = enclosingScrollView?.contentView else { return }
        let s = scaledSize
        let w = max(clip.bounds.width, s.width + 40)
        let h = max(clip.bounds.height, s.height + 40)
        setFrameSize(NSSize(width: w, height: h))
    }

    func imagePoint(from viewPoint: NSPoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: (viewPoint.x - r.minX) / zoom, y: (viewPoint.y - r.minY) / zoom)
    }

    func zoomToFit() {
        guard let clip = enclosingScrollView?.contentView else { return }
        let sx = (clip.bounds.width - 60) / document.size.width
        let sy = (clip.bounds.height - 60) / document.size.height
        zoom = max(0.05, min(sx, sy))
    }

    /// The part of the document currently on screen, in image coordinates,
    /// rounded outwards so partial pixels are not clipped.
    private func visibleImageRect(in imageRect: CGRect) -> CGRect {
        let visible = enclosingScrollView?.documentVisibleRect ?? bounds
        let region = CGRect(x: (visible.minX - imageRect.minX) / zoom,
                            y: (visible.minY - imageRect.minY) / zoom,
                            width: visible.width / zoom,
                            height: visible.height / zoom)
        return region.insetBy(dx: -1, dy: -1).integral.intersection(document.bounds)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        dirtyRect.intersection(bounds).fill()

        let r = imageRect
        drawCheckerboard(in: r, cell: 8)

        // Only the visible slice of the document is composited, at the size it
        // is about to be drawn. A 20000 x 20000 canvas then costs the same to
        // redraw as a small one.
        let visibleInImage = visibleImageRect(in: r)
        let backingScale = window?.backingScaleFactor ?? 2
        let pixelScale = min(zoom, 1) * backingScale
        if compositeDirty || cachedComposite == nil
            || cachedRegion != visibleInImage || cachedScale != pixelScale {
            let pixelSize = CGSize(width: visibleInImage.width * pixelScale,
                                   height: visibleInImage.height * pixelScale)
            cachedComposite = document.composite(region: visibleInImage, pixelSize: pixelSize)
            cachedRegion = visibleInImage
            cachedScale = pixelScale
            compositeDirty = false
        }
        ctx.saveGState()
        ctx.interpolationQuality = zoom >= 1 ? .none : .high
        if let img = cachedComposite {
            // Draw the slice back where it came from.
            let onScreen = CGRect(x: r.minX + visibleInImage.minX * zoom,
                                  y: r.minY + visibleInImage.minY * zoom,
                                  width: visibleInImage.width * zoom,
                                  height: visibleInImage.height * zoom)
            ctx.draw(img, in: onScreen)
        }
        ctx.restoreGState()

        // Tool overlay + selection are drawn in image space.
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.minY)
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.clip(to: document.bounds.insetBy(dx: -2 / zoom, dy: -2 / zoom))
        engine.viewScale = zoom
        engine.drawOverlay(in: ctx, scale: zoom)
        ctx.restoreGState()

        if let sel = document.selectionPath {
            ctx.saveGState()
            ctx.translateBy(x: r.minX, y: r.minY)
            ctx.scaleBy(x: zoom, y: zoom)
            ctx.setLineWidth(1 / zoom)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.addPath(sel); ctx.strokePath()
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineDash(phase: antsPhase / zoom, lengths: [4 / zoom, 4 / zoom])
            ctx.addPath(sel); ctx.strokePath()
            ctx.restoreGState()
        }

        drawBrushRing(in: ctx, imageRect: r)

        ctx.setStrokeColor(NSColor(calibratedWhite: 0.35, alpha: 1).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(r.insetBy(dx: -0.5, dy: -0.5))
    }

    /// Outlines what a brush or eraser is about to cover. Drawn in view space
    /// so the ring keeps a hairline outline at any zoom.
    private func drawBrushRing(in ctx: CGContext, imageRect r: CGRect) {
        guard settings.tool.hasBrushTip, let p = hoverPoint else { return }
        let radius = settings.brushWidth / 2 * zoom
        guard radius > 1 else { return }
        let center = CGPoint(x: r.minX + p.x * zoom, y: r.minY + p.y * zoom)
        let circle = CGRect(x: center.x - radius, y: center.y - radius,
                            width: radius * 2, height: radius * 2)
        ctx.saveGState()
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.strokeEllipse(in: circle.insetBy(dx: -0.5, dy: -0.5))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.strokeEllipse(in: circle.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
    }

    private func startAnts() {
        antsTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self, self.document.selectionPath != nil else { return }
            self.antsPhase = (self.antsPhase + 1).truncatingRemainder(dividingBy: 8)
            self.needsDisplay = true
        }
        RunLoop.main.add(antsTimer!, forMode: .common)
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) { handleDown(event, right: false) }
    override func rightMouseDown(with event: NSEvent) { handleDown(event, right: true) }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { super.otherMouseDown(with: event); return }
        panOrigin = convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.push()
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard panOrigin != nil else { super.otherMouseDragged(with: event); return }
        panBy(to: convert(event.locationInWindow, from: nil))
    }

    override func otherMouseUp(with event: NSEvent) {
        guard panOrigin != nil else { super.otherMouseUp(with: event); return }
        panOrigin = nil
        NSCursor.pop()
    }

    /// Scrolls the clip view so the point grabbed stays under the pointer.
    private func panBy(to vp: NSPoint) {
        guard let origin = panOrigin, let clip = enclosingScrollView?.contentView else { return }
        var o = clip.bounds.origin
        o.x -= vp.x - origin.x
        o.y -= vp.y - origin.y
        clip.scroll(to: o)
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    private func handleDown(_ event: NSEvent, right: Bool) {
        let vp = convert(event.locationInWindow, from: nil)
        let p = imagePoint(from: vp)

        switch settings.tool {
        case .pan:
            panOrigin = vp
            return
        case .zoom:
            if event.modifierFlags.contains(.option) || right { zoom /= 1.25 } else { zoom *= 1.25 }
            return
        case .text:
            delegate?.canvasWantsTextEntry(self, at: p)
            return
        default:
            break
        }
        window?.makeFirstResponder(self)
        engine.mouseDown(at: p, rightButton: right, modifiers: event.modifierFlags)
    }

    override func mouseDragged(with event: NSEvent) { handleDrag(event) }
    override func rightMouseDragged(with event: NSEvent) { handleDrag(event) }

    private func handleDrag(_ event: NSEvent) {
        let vp = convert(event.locationInWindow, from: nil)
        if settings.tool == .pan, panOrigin != nil {
            panBy(to: vp)
            return
        }
        hoverPoint = imagePoint(from: vp)
        engine.mouseDragged(to: imagePoint(from: vp), modifiers: event.modifierFlags)
        delegate?.canvas(self, didHoverAt: imagePoint(from: vp))
    }

    override func mouseUp(with event: NSEvent) { handleUp(event) }
    override func rightMouseUp(with event: NSEvent) { handleUp(event) }

    private func handleUp(_ event: NSEvent) {
        panOrigin = nil
        let p = imagePoint(from: convert(event.locationInWindow, from: nil))
        engine.mouseUp(at: p, modifiers: event.modifierFlags)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = imagePoint(from: convert(event.locationInWindow, from: nil))
        hoverPoint = p
        delegate?.canvas(self, didHoverAt: document.bounds.contains(p) ? p : nil)
    }

    override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        delegate?.canvas(self, didHoverAt: nil)
    }

    override func keyDown(with event: NSEvent) {
        let arrows: [UInt16: (CGFloat, CGFloat)] = [123: (-1, 0), 124: (1, 0), 125: (0, -1), 126: (0, 1)]
        switch event.keyCode {
        case 36, 76:  // Return / Enter
            if engine.session != nil { engine.commitSession() } else { super.keyDown(with: event) }
        case 51, 117: // Delete / Forward Delete
            delegate?.canvasWantsDelete(self)
        case 53:      // Escape
            if engine.session != nil { engine.cancelSession() } else { document.deselect() }
        case let code where arrows[code] != nil && engine.hasFloatingPixels:
            let (dx, dy) = arrows[event.keyCode]!
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            engine.nudgeFloatingPixels(dx: dx * step, dy: dy * step)
        case let code where arrows[code] != nil && engine.session != nil:
            let (dx, dy) = arrows[event.keyCode]!
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            if event.modifierFlags.contains(.option) {
                engine.adjustSession(dx: 0, dy: 0, rotation: (dx + dy) * .pi / 180 * step)
            } else {
                engine.adjustSession(dx: dx * step, dy: dy * step, rotation: 0)
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let factor = 1 + event.scrollingDeltaY * 0.01
            let old = zoom
            zoom = old * factor
            return
        }
        // Option turns the wheel into the tool's dial: size, tolerance,
        // gradient strength — whatever that tool is mostly about.
        if event.modifierFlags.contains(.option),
           let option = settings.adjustable(secondary: event.modifierFlags.contains(.shift)) {
            wheelSteps += event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY / 12
                : event.scrollingDeltaY
            let steps = wheelSteps.rounded(.towardZero)
            guard steps != 0 else { return }
            wheelSteps -= steps
            delegate?.canvas(self, didAdjustSetting: settings.adjust(option, steps: steps))
            needsDisplay = true
            return
        }
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        zoom *= (1 + event.magnification)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch settings.tool {
        case .pan:         cursor = .openHand
        case .text:        cursor = .iBeam
        case .colorPicker: cursor = .crosshair
        case .zoom:        cursor = .crosshair
        default:           cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }
}
