import AppKit
@testable import SketchyKit

// Minimal harness: `swift run SketchySelfTest` exits non-zero if anything fails.
var failures = 0
var checks = 0

func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition {
        failures += 1
        FileHandle.standardError.write(Data("FAIL  \(message)\n".utf8))
    }
}

func equal<T: Equatable>(_ a: T, _ b: T, _ message: String) {
    check(a == b, "\(message) — got \(a), expected \(b)")
}

func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat, _ message: String) {
    check(abs(a - b) <= tolerance, "\(message) — got \(a), expected \(b) ± \(tolerance)")
}

func pixel(_ doc: Document, _ x: Int, _ y: Int) -> PixelOps.RGBA? {
    guard let img = doc.composite() else { return nil }
    let l = Layer(width: img.width, height: img.height, name: "probe")
    l.draw(image: img)
    return PixelOps.sample(l, x: x, y: y)
}

func section(_ name: String) { print("• \(name)") }

/// Windows and panels need a window server, which a headless CI shell lacks.
let hasWindowServer = CGSessionCopyCurrentDictionary() != nil

func windowSection(_ name: String, _ body: () -> Void) {
    guard hasWindowServer else {
        print("• \(name) (skipped: no window server)")
        return
    }
    section(name)
    body()
}

// MARK: - New document

section("new document")
do {
    let doc = Document(width: 32, height: 16)
    equal(doc.width, 32, "document width")
    equal(doc.layers.count, 1, "layer count")
    let p = pixel(doc, 4, 4)
    equal(p?.r ?? 0, 255, "background is white")
    equal(p?.a ?? 0, 255, "background is opaque")
}

// MARK: - Painting and undo

section("pencil stroke, undo and redo")
do {
    let doc = Document(width: 32, height: 32)
    let settings = ToolSettings()
    settings.tool = .pencil
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.primaryColor = .red
    engine.mouseDown(at: CGPoint(x: 4, y: 4), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 20, y: 4), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 20, y: 4), modifiers: [])

    let sketchy = pixel(doc, 12, 4)
    equal(sketchy?.r ?? 0, 255, "stroke is red")
    check(Int(sketchy?.g ?? 255) < 40, "stroke removed green channel")

    check(doc.undo(), "undo succeeded")
    equal(pixel(doc, 12, 4)?.g ?? 0, 255, "undo restored white")
    check(doc.redo(), "redo succeeded")
    check(Int(pixel(doc, 12, 4)?.g ?? 255) < 40, "redo repainted")
}

// MARK: - Paint bucket

section("paint bucket")
do {
    let doc = Document(width: 24, height: 24)
    let settings = ToolSettings()
    settings.tool = .paintBucket
    settings.tolerance = 0.1
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.primaryColor = .blue
    engine.mouseDown(at: CGPoint(x: 12, y: 12), rightButton: false, modifiers: [])
    engine.mouseUp(at: CGPoint(x: 12, y: 12), modifiers: [])
    let p = pixel(doc, 1, 1)
    equal(p?.b ?? 0, 255, "flood filled the whole canvas")
    check(Int(p?.r ?? 255) < 40, "red channel cleared")
}

// MARK: - Selection clipping

section("selection clips painting")
do {
    let doc = Document(width: 32, height: 32)
    doc.selectionPath = CGPath(rect: CGRect(x: 0, y: 0, width: 8, height: 32), transform: nil)
    let settings = ToolSettings()
    settings.tool = .pencil
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.primaryColor = .red
    engine.mouseDown(at: CGPoint(x: 2, y: 16), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 30, y: 16), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 30, y: 16), modifiers: [])
    check(Int(pixel(doc, 4, 16)?.g ?? 255) < 40, "inside the selection is sketchy")
    equal(pixel(doc, 20, 16)?.g ?? 0, 255, "outside the selection is untouched")
}

// MARK: - Layers

section("layer stack")
do {
    let doc = Document(width: 8, height: 8)
    doc.addLayer()
    equal(doc.layers.count, 2, "added a layer")
    doc.duplicateSelectedLayer()
    equal(doc.layers.count, 3, "duplicated a layer")
    doc.mergeLayerDown()
    equal(doc.layers.count, 2, "merged down")
    doc.deleteSelectedLayer()
    equal(doc.layers.count, 1, "deleted a layer")
    doc.deleteSelectedLayer()
    equal(doc.layers.count, 1, "the last layer is kept")
}

section("opacity affects the composite")
do {
    let doc = Document(width: 8, height: 8)
    doc.addLayer()
    doc.selectedLayer?.fill(with: .black)
    doc.selectedLayer?.opacity = 0.5
    let p = pixel(doc, 4, 4)
    check(p != nil && p!.r > 100 && p!.r < 160, "half-opacity black over white is mid grey")
}

// MARK: - Geometry

section("canvas geometry")
do {
    let doc = Document(width: 20, height: 10)
    doc.rotate(turns: 1)
    equal(doc.width, 10, "rotate swapped width")
    equal(doc.height, 20, "rotate swapped height")
    doc.resizeImage(to: CGSize(width: 5, height: 5))
    equal(doc.width, 5, "resized image")
    doc.resizeCanvas(to: CGSize(width: 9, height: 9))
    equal(doc.height, 9, "resized canvas")
}

// MARK: - Shapes

section("shape geometry")
do {
    let r = CGRect(x: 0, y: 0, width: 100, height: 60)
    for kind in ShapeKind.allCases {
        let path = ShapeFactory.path(for: kind, in: r)
        check(!path.isEmpty, "\(kind.rawValue) has geometry")
        check(r.insetBy(dx: -1, dy: -1).contains(path.boundingBoxOfPath),
              "\(kind.rawValue) stays inside its bounds")
    }
}

// MARK: - File round trip

section("save and reopen")
do {
    let doc = Document(width: 16, height: 12)
    doc.selectedLayer?.fill(with: .green)
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("sketchy-selftest-\(UUID().uuidString).png")
    do {
        try doc.write(to: url)
        let reopened = try Document.open(url: url)
        equal(reopened.width, 16, "reopened width")
        equal(reopened.height, 12, "reopened height")
        equal(pixel(reopened, 8, 6)?.g ?? 0, 255, "reopened pixels survived")
    } catch {
        check(false, "round trip threw \(error)")
    }
    try? FileManager.default.removeItem(at: url)
}

// MARK: - History

section("history navigation")
do {
    let doc = Document(width: 8, height: 8)
    for _ in 0..<5 { doc.addLayer() }
    equal(doc.history.entries.count, 6, "history recorded every step")
    doc.jumpHistory(to: 0)
    equal(doc.layers.count, 1, "jumped back to the start")
    doc.jumpHistory(to: 5)
    equal(doc.layers.count, 6, "jumped forward again")
}

// MARK: - Magic wand

section("magic wand")
do {
    let doc = Document(width: 16, height: 16)
    doc.selectedLayer?.context.setFillColor(NSColor.black.cgColor)
    doc.selectedLayer?.context.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
    let settings = ToolSettings()
    settings.tool = .magicWand
    settings.tolerance = 0.05
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.mouseDown(at: CGPoint(x: 2, y: 8), rightButton: false, modifiers: [])
    engine.mouseUp(at: CGPoint(x: 2, y: 8), modifiers: [])
    if let box = doc.selectionPath?.boundingBoxOfPath {
        near(box.width, 8, 1, "wand selected the black half's width")
        near(box.height, 16, 1, "wand selected the full height")
    } else {
        check(false, "wand produced a selection")
    }
}

// MARK: - Effects

section("adjustments")
do {
    let doc = Document(width: 16, height: 16)
    doc.selectedLayer?.fill(with: NSColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1))
    let ok = ImageEffects.apply(ImageEffects.invert, to: doc.selectedLayer!, selection: nil)
    check(ok, "invert applied")
    if let p = pixel(doc, 8, 8) {
        check(p.r > 180 && p.b < 80, "colors were inverted (got r=\(p.r) g=\(p.g) b=\(p.b) a=\(p.a))")
    }
}

// MARK: - Native .ptd round trip

section("native .ptd document")
do {
    let doc = Document(width: 20, height: 14)
    doc.selectedLayer?.fill(with: .red)
    doc.addLayer(named: "Top")
    doc.selectedLayer?.fill(with: .blue)
    doc.selectedLayer?.opacity = 0.4
    doc.selectedLayer?.blendMode = .multiply
    doc.layers[0].isVisible = true

    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("sketchy-selftest-\(UUID().uuidString).sketchy")
    do {
        try doc.write(to: url)
        let reopened = try Document.open(url: url)
        equal(reopened.layers.count, 2, "layers survived the round trip")
        equal(reopened.width, 20, "width survived")
        equal(reopened.layers[1].name, "Top", "layer name survived")
        equal(reopened.layers[1].blendMode, .multiply, "blend mode survived")
        near(reopened.layers[1].opacity, 0.4, 0.01, "opacity survived")
        let base = PixelOps.sample(reopened.layers[0], x: 10, y: 7)
        equal(base?.r ?? 0, 255, "bottom layer pixels survived")
    } catch {
        check(false, "native round trip threw \(error)")
    }
    try? FileManager.default.removeItem(at: url)
}

// MARK: - Shape sessions

section("editable shape session")
do {
    let doc = Document(width: 100, height: 100)
    let settings = ToolSettings()
    settings.tool = .shapes
    settings.shape = .rectangle
    settings.drawMode = .fill
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.primaryColor = .black
    engine.secondaryColor = .red

    engine.mouseDown(at: CGPoint(x: 10, y: 10), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 40, y: 30), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 40, y: 30), modifiers: [])

    check(engine.session != nil, "the shape stays editable after the drag")
    equal(pixel(doc, 25, 20)?.r ?? 0, 255, "nothing is rasterized yet")

    // Drag from inside to move it.
    engine.mouseDown(at: CGPoint(x: 25, y: 20), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 65, y: 60), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 65, y: 60), modifiers: [])
    if let s = engine.session {
        near(s.center.x, 65, 1, "moved horizontally")
        near(s.center.y, 60, 1, "moved vertically")
    } else {
        check(false, "session survived the move")
    }

    // Drag outside the box to rotate it.
    let before = engine.session?.angle ?? 0
    engine.mouseDown(at: CGPoint(x: 95, y: 60), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 65, y: 90), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 65, y: 90), modifiers: [])
    near(abs((engine.session?.angle ?? 0) - before), .pi / 2, 0.2, "rotated a quarter turn")

    let steps = doc.history.entries.count
    check(engine.commitSession(), "commit rasterized the shape")
    check(engine.session == nil, "session cleared after commit")
    equal(doc.history.entries.count, steps + 1, "commit pushed one history step")
    // A filled shape uses the secondary color (red) for its interior.
    let fillPixel = pixel(doc, 65, 60)
    equal(fillPixel?.r ?? 0, 255, "shape interior is the secondary color")
    check(Int(fillPixel?.b ?? 255) < 40, "pixels landed where the shape was")
}

section("shape session cancel")
do {
    let doc = Document(width: 60, height: 60)
    let settings = ToolSettings()
    settings.tool = .shapes
    settings.shape = .ellipse
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.mouseDown(at: CGPoint(x: 10, y: 10), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 50, y: 50), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 50, y: 50), modifiers: [])
    engine.cancelSession()
    check(engine.session == nil, "cancel discards the shape")
    equal(pixel(doc, 30, 30)?.r ?? 0, 255, "canvas untouched after cancel")
}

// MARK: - Layer transform

section("rotate / zoom layer")
do {
    let doc = Document(width: 40, height: 40, background: nil)
    let layer = doc.selectedLayer!
    layer.context.setFillColor(NSColor.black.cgColor)
    layer.context.fill(CGRect(x: 0, y: 0, width: 40, height: 10))   // bar along the bottom
    doc.transformLayer(layer, angle: .pi / 2, scale: 1, offset: .zero)
    // +90° turns the bottom bar into a bar along the right edge.
    let right = PixelOps.sample(layer, x: 35, y: 20)
    let bottom = PixelOps.sample(layer, x: 20, y: 5)
    check((right?.a ?? 0) > 200, "the bar rotated onto its side")
    check((bottom?.a ?? 255) < 60, "the original position is now empty")
}

// MARK: - Erase

section("delete key erases")
do {
    let doc = Document(width: 40, height: 40)
    doc.selectedLayer?.fill(with: .black)

    // With a selection, only that region is cleared.
    doc.selectionPath = CGPath(rect: CGRect(x: 0, y: 0, width: 20, height: 40), transform: nil)
    check(doc.eraseSelection(), "erase reported success")
    check(Int(PixelOps.sample(doc.selectedLayer!, x: 5, y: 20)?.a ?? 255) < 20, "selected region is transparent")
    equal(PixelOps.sample(doc.selectedLayer!, x: 30, y: 20)?.a ?? 0, 255, "the rest is untouched")
    equal(doc.history.currentTitle, "Erase Selection", "history names the selection erase")

    // With nothing selected, the whole layer goes.
    doc.deselect()
    doc.eraseSelection()
    check(Int(PixelOps.sample(doc.selectedLayer!, x: 30, y: 20)?.a ?? 255) < 20, "whole layer cleared")
    equal(doc.history.currentTitle, "Erase Layer", "history names the layer erase")

    check(doc.undo(), "erase is undoable")
    equal(PixelOps.sample(doc.selectedLayer!, x: 30, y: 20)?.a ?? 0, 255, "undo brought the pixels back")
}

// MARK: - Responsive palettes

section("palette content reflows")
do {
    let tools = ToolsPaletteView(frame: NSRect(x: 0, y: 0, width: 84, height: 340))
    let twoCol = tools.preferredHeight(forWidth: 84) ?? 0
    let oneCol = tools.preferredHeight(forWidth: 44) ?? 0
    let wide = tools.preferredHeight(forWidth: 300) ?? 0
    check(oneCol > twoCol, "one column is taller than two")
    check(wide < twoCol, "a wide rail packs the tools into fewer rows")

    // Buttons must actually move, not just the reported height.
    tools.setFrameSize(NSSize(width: 44, height: oneCol))
    let narrowXs = Set(tools.subviews.map { Int($0.frame.minX) })
    tools.setFrameSize(NSSize(width: 300, height: wide))
    let wideXs = Set(tools.subviews.map { Int($0.frame.minX) })
    equal(narrowXs.count, 1, "one column of buttons when narrow")
    check(wideXs.count > 4, "many columns when wide")
    check(tools.subviews.allSatisfy { $0.frame.maxX <= 300 }, "buttons stay inside the view")

    let colors = ColorsPaletteView(frame: NSRect(x: 0, y: 0, width: 232, height: 380))
    let tall = colors.preferredHeight(forWidth: 232) ?? 0
    let short = colors.preferredHeight(forWidth: 110) ?? 0
    check(short < tall, "the color wheel shrinks with the rail")
    colors.setFrameSize(NSSize(width: 110, height: short))
    check(colors.wheel.frame.maxX <= 110, "the wheel fits the narrow width")
    check(colors.moreButton.isHidden, "More >> hides when there is no room")
    colors.setFrameSize(NSSize(width: 232, height: tall))
    check(!colors.moreButton.isHidden, "More >> comes back when there is room")
    check(colors.paletteView.frame.width > 180, "the swatch strip stretches")

    // The numeric fields wrap with the width and stay inside the palette.
    colors.setFrameSize(NSSize(width: 300, height: colors.preferredHeight(forWidth: 300) ?? 0))
    let wideRows = Set(colors.rgbaFields.map { Int($0.frame.minY) })
    equal(wideRows.count, 1, "R G B A share one row when there is room")
    check(colors.rgbaFields.allSatisfy { $0.frame.maxX <= 300 }, "fields stay inside the width")
    check(colors.hexField.frame.width > 200, "the hex field spans the palette")

    colors.setFrameSize(NSSize(width: 130, height: colors.preferredHeight(forWidth: 130) ?? 0))
    let narrowRows = Set(colors.rgbaFields.map { Int($0.frame.minY) })
    equal(narrowRows.count, 2, "R G B A wrap onto two rows when narrow")
    check(colors.rgbaFields.allSatisfy { $0.frame.maxX <= 130 }, "wrapped fields stay inside the width")
    // Nothing may overlap the swatch strip or the wheel above it.
    let lowestField = colors.hsvFields.map(\.frame.minY).min() ?? 0
    let highestField = colors.rgbaFields.map(\.frame.maxY).max() ?? 0
    check(lowestField > colors.paletteView.frame.maxY, "fields sit above the swatch strip")
    check(highestField < colors.wheel.frame.minY, "fields sit below the wheel")
}

windowSection("color fields drive the palette") {
    let panel = ColorsPanel()
    let fields = panel.palette

    func commit(_ field: NSTextField) {
        _ = field.target?.perform(field.action, with: field)
    }

    fields.hexField.stringValue = "#1E90FF"
    commit(fields.hexField)
    equal(panel.primary.hexString, "1E90FF", "typing hex sets the primary color")
    equal(fields.redField.integerValue, 30, "the R field follows the hex")
    equal(fields.blueField.integerValue, 255, "the B field follows the hex")

    fields.redField.integerValue = 10
    fields.greenField.integerValue = 20
    fields.blueField.integerValue = 30
    fields.alphaField.integerValue = 128
    commit(fields.redField)
    equal(panel.primary.hexString, "0A141E80", "RGBA entry sets the color, alpha included")

    fields.hueField.integerValue = 120
    fields.saturationField.integerValue = 100
    fields.valueField.integerValue = 100
    commit(fields.hueField)
    equal(panel.primary.rgbaBytes.g, 255, "HSV entry sets the color")

    // Garbage is rejected and the field snaps back to the current color.
    let before = panel.primary.hexString
    fields.hexField.stringValue = "zzz"
    commit(fields.hexField)
    equal(panel.primary.hexString, before, "invalid hex leaves the color alone")
    equal(fields.hexField.stringValue, before, "invalid hex is replaced by the current value")

    // Picking elsewhere refreshes the fields.
    panel.setColor(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), secondary: false)
    equal(fields.hexField.stringValue, "FF0000", "picking a color updates the fields")
    equal(fields.hueField.integerValue, 0, "red reads as hue 0")
}

// MARK: - Docking

windowSection("palette docking") {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    let manager = DockManager(window: window)
    window.contentView?.addSubview(manager.leftRail)
    window.contentView?.addSubview(manager.rightRail)

    let panel = FloatingPanel(title: "Layers", size: NSSize(width: 262, height: 360))
    _ = panel.contentView
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 262, height: 360))
    let marker = NSTextField(labelWithString: "layer list")
    content.addSubview(marker)
    panel.contentView = content
    let palette = Palette(id: "layers", title: "Layers", panel: panel, dockedHeight: nil)
    manager.register(palette)

    equal(palette.side, .floating, "palettes start floating")

    manager.dock(palette, to: .right)
    equal(palette.side, .right, "docked to the right rail")
    check(!manager.rightRail.isEmpty, "the rail holds a box")
    check(marker.window === window, "the palette's controls moved into the main window")
    check(!panel.isVisible, "the floating panel is hidden while docked")

    manager.dock(palette, to: .left)
    equal(palette.side, .left, "moved across to the left rail")
    check(manager.rightRail.isEmpty, "the old rail released it")
    equal(manager.leftRail.boxes.count, 1, "the new rail owns exactly one box")

    manager.float(palette)
    equal(palette.side, .floating, "torn back off into its panel")
    check(manager.leftRail.isEmpty, "the rail is empty again")
    check(marker.window === panel, "the controls returned to the panel")

    // A collapsed box shrinks to its header.
    manager.dock(palette, to: .left)
    if let box = palette.box {
        let expanded = box.fittingHeight(available: 400)
        box.isCollapsed = true
        equal(box.fittingHeight(available: 400), DockedPaletteBox.headerHeight, "collapsed to the header")
        check(expanded > DockedPaletteBox.headerHeight, "expanded is taller than collapsed")
    } else {
        check(false, "docking produced a box")
    }
    manager.resetLayout()
    equal(palette.side, .floating, "reset floats everything again")
}

// MARK: - Tabs share one set of palettes

windowSection("document commands land a floating paste first") {
    let hub = PaletteHub()
    let controller = MainWindowController(doc: Document(width: 40, height: 20), hub: hub)
    let doc = controller.doc

    let clip = Layer(width: 10, height: 10, name: "clip")
    clip.fill(with: .red)
    controller.selectTool(.moveSelectedPixels)
    controller.engine.beginFloatingPaste(clip.image!, at: CGPoint(x: 5, y: 5))
    check(controller.engine.hasFloatingPixels, "the paste is floating")

    // Rotating rebuilds every layer from its bitmap, so a paste left hovering
    // would be thrown away.
    controller.rotate90CW(nil)
    check(!controller.engine.hasFloatingPixels, "rotating landed the paste")
    equal(doc.width, 20, "the canvas rotated")
    equal(doc.height, 40, "both ways")

    let landed = doc.composite().map { image -> Bool in
        let probe = Layer(width: image.width, height: image.height, name: "probe")
        probe.draw(image: image)
        for y in 0..<image.height {
            for x in 0..<image.width {
                if let p = PixelOps.sample(probe, x: x, y: y), p.r > 200, p.g < 60, p.b < 60 {
                    return true
                }
            }
        }
        return false
    } ?? false
    check(landed, "the pasted pixels are still in the document after the rotation")

    // The same guard covers the other document-wide commands.
    controller.engine.beginFloatingPaste(clip.image!, at: CGPoint(x: 2, y: 2))
    controller.flattenImage(nil)
    check(!controller.engine.hasFloatingPixels, "flattening landed it too")
}

windowSection("palettes stay out of the way") {
    let hub = PaletteHub()
    let panels = [hub.toolsPanel, hub.colorsPanel, hub.historyPanel, hub.layersPanel]

    check(!hub.keepsPalettesInFront, "palettes are not pinned in front by default")
    check(panels.allSatisfy { $0.level == .normal },
          "so they sit in the normal window order")
    check(panels.allSatisfy { !$0.isFloatingPanel },
          "and do not behave as floating panels")

    hub.keepsPalettesInFront = true
    check(panels.allSatisfy { $0.level == .floating }, "turning the setting on pins them")
    check(panels.allSatisfy { $0.isFloatingPanel }, "as floating panels")

    hub.keepsPalettesInFront = false
    check(panels.allSatisfy { $0.level == .normal }, "and turning it off releases them")

    // Palettes still survive the app losing focus either way.
    check(panels.allSatisfy { !$0.hidesOnDeactivate },
          "they do not vanish when another app is used")
}

windowSection("palettes follow the active tab") {
    let hub = PaletteHub()
    let first = MainWindowController(doc: Document(width: 100, height: 80), hub: hub)
    check(hub.activeController === first, "the first tab owns the palettes")

    if let layers = hub.dock.palette(id: "layers") {
        hub.dock.dock(layers, to: .right)
        check(first.rightRail.boxes.count == 1, "docked into the first tab's rail")

        let second = MainWindowController(doc: Document(width: 60, height: 40), hub: hub)
        check(hub.activeController === second, "creating a tab moves the palettes to it")
        check(first.rightRail.isEmpty, "the old tab's rail is empty again")
        equal(second.rightRail.boxes.count, 1, "the new tab's rail holds the palette")
        equal(layers.side, .right, "the palette stayed docked through the move")

        // Palette callbacks must act on the newly active document.
        hub.layersPanel.onAdd?()
        equal(second.doc.layers.count, 2, "the Layers palette edits the active tab")
        equal(first.doc.layers.count, 1, "the background tab is untouched")

        // Switching back returns the palettes.
        hub.attach(to: first)
        check(second.rightRail.isEmpty, "rails follow the active tab both ways")
        equal(first.rightRail.boxes.count, 1, "palette came back to the first tab")

        // Rail width survives the hand-off.
        first.rightRail.width = 210
        hub.attach(to: second)
        near(second.rightRail.width, 210, 0.5, "rail width carries across tabs")
    } else {
        check(false, "the hub registered a Layers palette")
    }

    // One shared set of panels, not one per tab.
    equal(hub.toolsPanel, first.toolsPanel, "tabs share the Tools palette")
    equal(hub.colorsPanel, first.colorsPanel, "tabs share the Colors palette")
}

section("size sheet keeps proportions")
do {
    let widthField = NSTextField(string: "800")
    let heightField = NSTextField(string: "600")
    let ratio = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    ratio.state = .on
    let linker = AspectLinker(width: widthField, height: heightField, ratio: ratio, aspect: 800.0 / 600.0)

    widthField.integerValue = 400
    linker.widthChanged()
    equal(heightField.integerValue, 300, "height follows width")

    heightField.integerValue = 150
    linker.heightChanged()
    equal(widthField.integerValue, 200, "width follows height")

    ratio.state = .off
    widthField.integerValue = 1000
    linker.widthChanged()
    equal(heightField.integerValue, 150, "unlinked fields stay put")
}

section("documents from before the rename still open")
do {
    let doc = Document(width: 12, height: 9)
    doc.selectedLayer?.fill(with: .green)
    let legacy = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("sketchy-legacy-\(UUID().uuidString).ptd")
    do {
        try doc.write(to: legacy)
        check(Document.isNative(legacy), ".ptd still counts as a layered document")

        // Rewrite the format marker the way the old build wrote it.
        var plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: legacy), options: [], format: nil) as? [String: Any] ?? [:]
        plist["format"] = "Painted Document"
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            .write(to: legacy)

        let reopened = try Document.open(url: legacy)
        equal(reopened.width, 12, "an old file opens by its old marker")
        equal(pixel(reopened, 6, 4)?.g ?? 0, 255, "with its pixels intact")
    } catch {
        check(false, "legacy round trip threw \(error)")
    }
    try? FileManager.default.removeItem(at: legacy)
}

// MARK: - Floating pixels

section("an oversized paste survives being moved")
do {
    // Canvas is 20x20; the pasted image is 40x40 with a red mark in one corner.
    let doc = Document(width: 20, height: 20)
    let clip = Layer(width: 40, height: 40, name: "clip")
    clip.fill(with: .blue)
    clip.context.setFillColor(NSColor.red.cgColor)
    clip.context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))   // bottom-left of the clip

    let settings = ToolSettings()
    settings.tool = .moveSelectedPixels
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.beginFloatingPaste(clip.image!, at: CGPoint(x: -10, y: -10))

    check(engine.hasFloatingPixels, "the paste is floating, not drawn")
    equal(doc.history.entries.count, 1, "nothing is committed yet")
    equal(pixel(doc, 10, 10)?.r ?? 0, 255, "the layer is untouched while floating")

    // Drag it far off the canvas, then back: the pixels are still all there.
    engine.mouseDown(at: CGPoint(x: 5, y: 5), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 200, y: 200), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 200, y: 200), modifiers: [])
    check(engine.hasFloatingPixels, "still floating after a drag off canvas")

    engine.mouseDown(at: CGPoint(x: 200, y: 200), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 15, y: 15), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 15, y: 15), modifiers: [])
    // The first drag pushed it +195, the second pulled it back -185.
    near(engine.floatingRect.minX, 0, 0.5, "a second drag continues from where it stopped")

    // Nudge the red corner into view, then drop it.
    engine.nudgeFloatingPixels(dx: 10, dy: 10)
    near(engine.floatingRect.minX, 10, 0.5, "nudging moves it further")
    check(engine.commitFloatingPixels(), "the drop lands")
    check(!engine.hasFloatingPixels, "nothing is floating afterwards")
    equal(doc.history.currentTitle, "Paste", "one history step for the paste")

    // The clip landed at (10, 10), so its red corner covers 10...18.
    let corner = pixel(doc, 14, 14)
    equal(corner?.r ?? 0, 255, "the red corner made it onto the canvas")
    check(Int(corner?.b ?? 255) < 60, "and it is red, not the blue field")
}

section("pasted pixels are not resampled")
do {
    // Two hard-edged halves: any smoothing shows up as a blended column.
    let doc = Document(width: 40, height: 40)
    let clip = Layer(width: 8, height: 8, name: "clip")
    clip.context.setFillColor(NSColor.red.cgColor)
    clip.context.fill(CGRect(x: 0, y: 0, width: 4, height: 8))
    clip.context.setFillColor(NSColor.blue.cgColor)
    clip.context.fill(CGRect(x: 4, y: 0, width: 4, height: 8))

    let settings = ToolSettings()
    settings.tool = .moveSelectedPixels
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.beginFloatingPaste(clip.image!, at: CGPoint(x: 10, y: 10))

    // Drag with a fractional delta, the way a real pointer moves.
    engine.mouseDown(at: CGPoint(x: 14, y: 14), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 22.4, y: 22.6), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 22.4, y: 22.6), modifiers: [])
    let frame = engine.floatingRect
    equal(frame.origin.x.truncatingRemainder(dividingBy: 1), 0, "the frame snaps to whole pixels")
    equal(frame.origin.y.truncatingRemainder(dividingBy: 1), 0, "vertically too")
    engine.commitFloatingPixels()

    let left = pixel(doc, Int(frame.minX) + 1, Int(frame.minY) + 4)
    let right = pixel(doc, Int(frame.minX) + 6, Int(frame.minY) + 4)
    equal(left?.r ?? 0, 255, "the red half stayed pure red")
    equal(left?.b ?? 255, 0, "with no blue bleeding in")
    equal(right?.b ?? 0, 255, "the blue half stayed pure blue")
    equal(right?.r ?? 255, 0, "with no red bleeding in")
}

section("resizing floating pixels")
do {
    let doc = Document(width: 60, height: 60)
    let clip = Layer(width: 10, height: 10, name: "clip")
    clip.fill(with: .red)

    let settings = ToolSettings()
    settings.tool = .moveSelectedPixels
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.beginFloatingPaste(clip.image!, at: CGPoint(x: 10, y: 10))

    // Grabbing a corner scales the pixels instead of moving them.
    let corner = engine.floatingHandles()[4]
    equal(corner, CGPoint(x: 20, y: 20), "the corner handle sits on the frame")
    engine.mouseDown(at: corner, rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 50, y: 40), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 50, y: 40), modifiers: [])
    equal(engine.floatingRect, CGRect(x: 10, y: 10, width: 40, height: 30), "the frame follows the handle")

    engine.commitFloatingPixels()
    equal(pixel(doc, 45, 35)?.r ?? 0, 255, "pixels cover the enlarged area")
    check(Int(pixel(doc, 45, 35)?.g ?? 255) < 60, "and kept their colour")
    check(Int(pixel(doc, 55, 35)?.g ?? 0) > 200, "beyond the frame is untouched")

    // Shift keeps the proportions.
    engine.beginFloatingPaste(clip.image!, at: CGPoint(x: 0, y: 0))
    engine.mouseDown(at: engine.floatingHandles()[4], rightButton: false, modifiers: [.shift])
    engine.mouseDragged(to: CGPoint(x: 40, y: 15), modifiers: [.shift])
    engine.mouseUp(at: CGPoint(x: 40, y: 15), modifiers: [.shift])
    equal(engine.floatingRect.width, engine.floatingRect.height, "shift keeps it square")
    engine.cancelFloatingPixels()
}

section("small floating blocks still move")
do {
    // Regression: handles used to cover the whole interior of a small block.
    let doc = Document(width: 60, height: 60)
    let clip = Layer(width: 10, height: 10, name: "clip")
    clip.fill(with: .red)

    let settings = ToolSettings()
    settings.tool = .moveSelectedPixels
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.beginFloatingPaste(clip.image!, at: CGPoint(x: 10, y: 10))

    engine.mouseDown(at: CGPoint(x: 15, y: 15), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 35, y: 35), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 35, y: 35), modifiers: [])
    equal(engine.floatingRect.size, CGSize(width: 10, height: 10), "a drag from the middle does not resize")
    equal(engine.floatingRect.origin, CGPoint(x: 30, y: 30), "it moves instead")
    engine.cancelFloatingPixels()
}

section("floating pixels can be put back")
do {
    let doc = Document(width: 30, height: 30, background: nil)
    doc.selectedLayer?.context.setFillColor(NSColor.red.cgColor)
    doc.selectedLayer?.context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
    doc.selectionPath = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)

    let settings = ToolSettings()
    settings.tool = .moveSelectedPixels
    let engine = ToolEngine(doc: doc, settings: settings)

    // Lifting empties the source, dragging moves the floating copy.
    engine.mouseDown(at: CGPoint(x: 5, y: 5), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 25, y: 25), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 25, y: 25), modifiers: [])
    check(Int(pixel(doc, 5, 5)?.a ?? 255) < 60, "the pixels left their old spot")

    // Escape puts them back exactly where they were.
    engine.cancelFloatingPixels()
    check(!engine.hasFloatingPixels, "the float is gone")
    equal(pixel(doc, 5, 5)?.r ?? 0, 255, "the lifted pixels are restored")
    equal(doc.history.entries.count, 1, "a cancelled move leaves no history")

    // Committing a real move writes to the new spot only.
    engine.mouseDown(at: CGPoint(x: 5, y: 5), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 25, y: 25), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 25, y: 25), modifiers: [])
    engine.commitFloatingPixels()
    equal(pixel(doc, 25, 25)?.r ?? 0, 255, "the pixels landed at the new spot")
    check(Int(pixel(doc, 5, 5)?.a ?? 255) < 60, "and left the old one empty")
    equal(doc.history.currentTitle, "Move Selected Pixels", "one history step for the move")
}

section("mask outlines are boundary loops")
do {
    // A solid block should come out as one four-corner loop, not a stack of
    // one-row rectangles that stroke every internal edge.
    var mask = [Bool](repeating: false, count: 20 * 20)
    for y in 5..<15 { for x in 4..<12 { mask[y * 20 + x] = true } }
    let block = PixelOps.path(from: mask, width: 20, height: 20)

    var elements = 0
    block.applyWithBlock { _ in elements += 1 }
    // move, three lines, and a close that draws the fourth side.
    equal(elements, 5, "a rectangle traces as four corners")
    equal(block.boundingBoxOfPath, CGRect(x: 4, y: 5, width: 8, height: 10), "covering the block")
    check(block.contains(CGPoint(x: 8, y: 10), using: .evenOdd), "the inside fills")
    check(!block.contains(CGPoint(x: 2, y: 10), using: .evenOdd), "the outside does not")

    // A ring: the hole has to come out as its own loop so it stays unselected.
    var ring = [Bool](repeating: false, count: 20 * 20)
    for y in 4..<16 { for x in 4..<16 { ring[y * 20 + x] = true } }
    for y in 8..<12 { for x in 8..<12 { ring[y * 20 + x] = false } }
    let ringPath = PixelOps.path(from: ring, width: 20, height: 20)
    check(ringPath.contains(CGPoint(x: 5, y: 10), using: .evenOdd), "the ring itself is inside")
    check(!ringPath.contains(CGPoint(x: 10, y: 10), using: .evenOdd), "the hole is not")

    // Two separate blobs stay separate.
    var pair = [Bool](repeating: false, count: 20 * 20)
    for y in 2..<5 { for x in 2..<5 { pair[y * 20 + x] = true } }
    for y in 14..<18 { for x in 14..<18 { pair[y * 20 + x] = true } }
    let pairPath = PixelOps.path(from: pair, width: 20, height: 20)
    check(pairPath.contains(CGPoint(x: 3, y: 3), using: .evenOdd), "the first blob is inside")
    check(pairPath.contains(CGPoint(x: 16, y: 16), using: .evenOdd), "so is the second")
    check(!pairPath.contains(CGPoint(x: 10, y: 10), using: .evenOdd), "the gap between them is not")
}

section("wand and bucket land on the right rows")
do {
    // Asymmetric on purpose: a band across the top only. A vertical flip in the
    // mask maths would put the result at the bottom and go unnoticed on a
    // symmetric shape.
    let doc = Document(width: 60, height: 40)
    let layer = doc.selectedLayer!
    layer.context.setFillColor(NSColor.black.cgColor)
    layer.context.fill(CGRect(x: 0, y: 30, width: 60, height: 10))   // top band

    let settings = ToolSettings()
    settings.tool = .magicWand
    settings.tolerance = 0.05
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.mouseDown(at: CGPoint(x: 30, y: 35), rightButton: false, modifiers: [])
    engine.mouseUp(at: CGPoint(x: 30, y: 35), modifiers: [])

    equal(doc.selectionPath?.boundingBoxOfPath ?? .zero, CGRect(x: 0, y: 30, width: 60, height: 10),
          "the wand selects the band it was clicked on")
    check(doc.selectionPath?.contains(CGPoint(x: 30, y: 35)) ?? false, "the clicked pixel is inside")
    check(!(doc.selectionPath?.contains(CGPoint(x: 30, y: 5)) ?? true), "the opposite band is not")

    // An off-centre corner, to catch a horizontal slip too.
    let corner = Document(width: 60, height: 40)
    corner.selectedLayer?.context.setFillColor(NSColor.blue.cgColor)
    corner.selectedLayer?.context.fill(CGRect(x: 40, y: 0, width: 20, height: 12))
    let cornerEngine = ToolEngine(doc: corner, settings: settings)
    cornerEngine.mouseDown(at: CGPoint(x: 50, y: 6), rightButton: false, modifiers: [])
    cornerEngine.mouseUp(at: CGPoint(x: 50, y: 6), modifiers: [])
    equal(corner.selectionPath?.boundingBoxOfPath ?? .zero, CGRect(x: 40, y: 0, width: 20, height: 12),
          "the wand finds a bottom-right block where it actually is")

    // The bucket shares the same mask maths.
    let bucketDoc = Document(width: 60, height: 40)
    bucketDoc.selectedLayer?.context.setFillColor(NSColor.black.cgColor)
    bucketDoc.selectedLayer?.context.fill(CGRect(x: 0, y: 30, width: 60, height: 10))
    let bucketSettings = ToolSettings()
    bucketSettings.tool = .paintBucket
    bucketSettings.tolerance = 0.05
    let bucket = ToolEngine(doc: bucketDoc, settings: bucketSettings)
    bucket.primaryColor = .red
    bucket.mouseDown(at: CGPoint(x: 30, y: 35), rightButton: false, modifiers: [])
    bucket.mouseUp(at: CGPoint(x: 30, y: 35), modifiers: [])

    equal(pixel(bucketDoc, 30, 35)?.r ?? 0, 255, "the bucket filled the band that was clicked")
    check(Int(pixel(bucketDoc, 30, 35)?.b ?? 255) < 60, "and it is red")
    equal(pixel(bucketDoc, 30, 5)?.r ?? 0, 255, "the untouched area is still white")
    equal(pixel(bucketDoc, 30, 5)?.b ?? 0, 255, "and still has its blue channel")
}

section("scaling keeps pixels hard-edged")
do {
    // A 2x2 checker blown up 8x: nearest neighbour keeps four solid blocks,
    // smoothing turns the middle into a gradient.
    func checker() -> Document {
        let doc = Document(width: 2, height: 2, background: nil)
        let layer = doc.selectedLayer!
        layer.context.setFillColor(NSColor.black.cgColor)
        layer.context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        layer.context.fill(CGRect(x: 1, y: 1, width: 1, height: 1))
        layer.context.setFillColor(NSColor.white.cgColor)
        layer.context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        layer.context.fill(CGRect(x: 0, y: 1, width: 1, height: 1))
        return doc
    }

    let hard = checker()
    hard.resizeImage(to: CGSize(width: 16, height: 16), resampling: .pixels)
    let blackBlock = pixel(hard, 3, 3)
    let whiteBlock = pixel(hard, 12, 3)
    equal(blackBlock?.r ?? 255, 0, "the black quarter stayed black")
    equal(whiteBlock?.r ?? 0, 255, "the white quarter stayed white")
    // The boundary must be a hard step, not a ramp.
    let left = pixel(hard, 7, 3)?.r ?? 0
    let right = pixel(hard, 8, 3)?.r ?? 0
    check(abs(Int(left) - Int(right)) > 200, "the edge between them is a hard step")

    let soft = checker()
    soft.resizeImage(to: CGSize(width: 16, height: 16), resampling: .smooth)
    let softLeft = soft.selectedLayer.flatMap { PixelOps.sample($0, x: 7, y: 3)?.r } ?? 0
    let softRight = soft.selectedLayer.flatMap { PixelOps.sample($0, x: 8, y: 3)?.r } ?? 0
    check(abs(Int(softLeft) - Int(softRight)) < 200, "smoothing blends the same edge")

    equal(ToolSettings().resampling, .pixels, "pixel art is the default")
}

section("resizing past an edge flips the pixels")
do {
    // Left half red, right half blue: a horizontal flip swaps them.
    let doc = Document(width: 60, height: 40)
    let clip = Layer(width: 20, height: 10, name: "clip")
    clip.context.setFillColor(NSColor.red.cgColor)
    clip.context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
    clip.context.setFillColor(NSColor.blue.cgColor)
    clip.context.fill(CGRect(x: 10, y: 0, width: 10, height: 10))

    let settings = ToolSettings()
    settings.tool = .moveSelectedPixels
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.beginFloatingPaste(clip.image!, at: CGPoint(x: 20, y: 20))

    // Grab the right edge and drag it well past the left edge.
    let rightEdge = engine.floatingHandles()[3]
    equal(rightEdge, CGPoint(x: 40, y: 25), "the right-edge handle is where it should be")
    engine.mouseDown(at: rightEdge, rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 0, y: 25), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 0, y: 25), modifiers: [])

    let frame = engine.floatingRect
    check(engine.floatingIsMirrored.x, "the drag past the edge mirrored horizontally")
    check(!engine.floatingIsMirrored.y, "and left the vertical alone")
    check(frame.width > 0 && frame.height > 0, "the frame stays a real rectangle")
    near(frame.maxX, 20, 1, "it now sits to the left of the anchor")
    engine.commitFloatingPixels()

    // Red started on the left; after mirroring it is on the right.
    let leftSample = pixel(doc, Int(frame.minX) + 2, 25)
    let rightSample = pixel(doc, Int(frame.maxX) - 2, 25)
    equal(leftSample?.b ?? 0, 255, "blue is on the left after the flip")
    equal(rightSample?.r ?? 0, 255, "red is on the right after the flip")
}

section("resizing without crossing does not mirror")
do {
    let doc = Document(width: 60, height: 40)
    let clip = Layer(width: 20, height: 10, name: "clip")
    clip.context.setFillColor(NSColor.red.cgColor)
    clip.context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
    clip.context.setFillColor(NSColor.blue.cgColor)
    clip.context.fill(CGRect(x: 10, y: 0, width: 10, height: 10))

    let settings = ToolSettings()
    settings.tool = .moveSelectedPixels
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.beginFloatingPaste(clip.image!, at: CGPoint(x: 20, y: 20))

    // Shrink from the right without passing the left edge.
    engine.mouseDown(at: engine.floatingHandles()[3], rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 30, y: 25), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 30, y: 25), modifiers: [])
    check(!engine.floatingIsMirrored.x, "shrinking does not mirror")
    equal(engine.floatingRect, CGRect(x: 20, y: 20, width: 10, height: 10), "the anchor edge held")

    // Vertical: drag the top handle below the bottom edge.
    engine.mouseDown(at: engine.floatingHandles()[5], rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 25, y: 5), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 25, y: 5), modifiers: [])
    check(engine.floatingIsMirrored.y, "dragging the top past the bottom mirrors vertically")
    check(!engine.floatingIsMirrored.x, "and leaves the horizontal alone")
    engine.cancelFloatingPixels()
}

section("scaled floating pixels stay hard-edged")
do {
    // Two-pixel wide clip blown up: with Pixels scaling the seam stays a step.
    let doc = Document(width: 40, height: 40, background: nil)
    let clip = Layer(width: 2, height: 1, name: "clip")
    clip.context.setFillColor(NSColor.black.cgColor)
    clip.context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    clip.context.setFillColor(NSColor.white.cgColor)
    clip.context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))

    let settings = ToolSettings()
    settings.tool = .moveSelectedPixels
    settings.resampling = .pixels
    let engine = ToolEngine(doc: doc, settings: settings)
    engine.beginFloatingPaste(clip.image!, at: CGPoint(x: 0, y: 0))
    engine.mouseDown(at: engine.floatingHandles()[4], rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 40, y: 20), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 40, y: 20), modifiers: [])
    engine.commitFloatingPixels()

    let left = pixel(doc, 19, 10)?.r ?? 0
    let right = pixel(doc, 21, 10)?.r ?? 0
    check(abs(Int(left) - Int(right)) > 200, "the seam is a hard step, not a gradient")
}

section("selection size is reported while dragging")
do {
    let doc = Document(width: 100, height: 100)
    let settings = ToolSettings()
    settings.tool = .rectangleSelect
    let engine = ToolEngine(doc: doc, settings: settings)

    check(engine.measuredRect == nil, "nothing to measure before a selection exists")

    // Mid-drag the marquee reports its live size, not the old selection's.
    engine.mouseDown(at: CGPoint(x: 10, y: 20), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 45, y: 70), modifiers: [])
    equal(engine.measuredRect?.width ?? 0, 35, "width updates during the drag")
    equal(engine.measuredRect?.height ?? 0, 50, "height updates during the drag")

    engine.mouseUp(at: CGPoint(x: 45, y: 70), modifiers: [])
    equal(engine.measuredRect ?? .zero, CGRect(x: 10, y: 20, width: 35, height: 50),
          "the committed selection keeps reporting its size")

    // An ellipse reports the box it fills.
    settings.tool = .ellipseSelect
    engine.mouseDown(at: CGPoint(x: 0, y: 0), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 20, y: 12), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 20, y: 12), modifiers: [])
    equal(engine.measuredRect?.width ?? 0, 20, "an ellipse measures its bounds")

    doc.deselect()
    check(engine.measuredRect == nil, "deselecting clears the readout")

    // Floating pixels report their own size, so a resize can be measured.
    settings.tool = .moveSelectedPixels
    let clip = Layer(width: 16, height: 9, name: "clip")
    clip.fill(with: .red)
    engine.beginFloatingPaste(clip.image!, at: CGPoint(x: 5, y: 5))
    equal(engine.measuredRect ?? .zero, CGRect(x: 5, y: 5, width: 16, height: 9),
          "pasted pixels report their size")
    engine.mouseDown(at: engine.floatingHandles()[4], rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 45, y: 35), modifiers: [])
    equal(engine.measuredRect?.width ?? 0, 40, "resizing updates the reported width")
    engine.cancelFloatingPixels()

    // A shape being placed measures too.
    settings.tool = .shapes
    settings.shape = .rectangle
    engine.mouseDown(at: CGPoint(x: 30, y: 30), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 60, y: 45), modifiers: [])
    near(engine.measuredRect?.width ?? 0, 30, 0.6, "a shape reports its width as it is drawn")
    near(engine.measuredRect?.height ?? 0, 15, 0.6, "and its height")
}

section("oversized paste choices")
do {
    let doc = Document(width: 40, height: 30)
    let big = CGSize(width: 100, height: 20)
    check(doc.exceedsCanvas(big), "wider than the canvas counts as oversized")
    check(doc.exceedsCanvas(CGSize(width: 10, height: 90)), "taller counts too")
    check(!doc.exceedsCanvas(CGSize(width: 40, height: 30)), "an exact fit does not")

    let current = doc.size
    equal(Document.PasteFit.expandCanvas.canvasSize(current: current, imageSize: big),
          CGSize(width: 100, height: 30), "expanding grows only the axes that need it")
    equal(Document.PasteFit.cropToImage.canvasSize(current: current, imageSize: big),
          big, "cropping takes the image's size exactly")
    equal(Document.PasteFit.keepCanvas.canvasSize(current: current, imageSize: big),
          current, "keeping leaves the canvas alone")

    // Expanding anchors the existing art at the top left.
    doc.selectedLayer?.context.setFillColor(NSColor.red.cgColor)
    doc.selectedLayer?.context.fill(CGRect(x: 0, y: 20, width: 10, height: 10))
    doc.resizeCanvas(to: Document.PasteFit.expandCanvas.canvasSize(current: current, imageSize: big),
                     anchor: CGPoint(x: 0, y: 1))
    equal(doc.width, 100, "canvas widened")
    equal(doc.height, 30, "height untouched")
    equal(pixel(doc, 5, 25)?.r ?? 0, 255, "the old art stayed in the top-left corner")
}

section("tool shortcuts")
do {
    let suite = "SketchySelfTest-\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suite)!
    var shortcuts = ToolShortcuts(store: store)

    equal(shortcuts.key(for: .paintbrush), "b", "the shipped key for the brush")
    equal(shortcuts.key(for: .eraser), "e", "and for the eraser")

    // The three selection tools share one key and cycle in palette order.
    let sharing = shortcuts.tools(for: "s")
    equal(sharing, [.rectangleSelect, .lassoSelect, .ellipseSelect], "selection tools share S")
    equal(shortcuts.nextTool(for: "s", after: .rectangleSelect), .lassoSelect, "S walks to the next")
    equal(shortcuts.nextTool(for: "s", after: .ellipseSelect), .rectangleSelect, "and wraps around")
    equal(shortcuts.nextTool(for: "b", after: .eraser), .paintbrush, "a key not on the current tool jumps to it")
    check(shortcuts.nextTool(for: "9", after: .paintbrush) == nil, "an unassigned key does nothing")

    // Rebinding.
    shortcuts.setKey("Q", for: .paintbrush)
    equal(shortcuts.key(for: .paintbrush), "q", "keys are stored lowercase")
    equal(shortcuts.nextTool(for: "q", after: .eraser), .paintbrush, "the new key works")
    check(shortcuts.nextTool(for: "b", after: .eraser) == nil, "the old key no longer does")

    shortcuts.setKey("", for: .eraser)
    check(shortcuts.key(for: .eraser) == nil, "an empty key unassigns the tool")
    shortcuts.setKey("longer", for: .pencil)
    equal(shortcuts.key(for: .pencil), "l", "only the first character is kept")

    // Changes survive a restart.
    shortcuts = ToolShortcuts(store: store)
    equal(shortcuts.key(for: .paintbrush), "q", "rebinding is remembered")
    check(shortcuts.key(for: .eraser) == nil, "so is unassigning")

    shortcuts.reset()
    equal(shortcuts.key(for: .paintbrush), "b", "restoring defaults brings the shipped keys back")
    equal(shortcuts.key(for: .eraser), "e", "for every tool")

    store.removePersistentDomain(forName: suite)
}

section("canvas size limits")
do {
    let sixteenGB = 16_000_000_000

    // Ordinary sizes are waved through.
    equal(Document.verdict(width: 800, height: 600, physicalMemory: sixteenGB), .fine,
          "a normal canvas is fine")
    equal(Document.verdict(width: 4000, height: 3000, layers: 3, physicalMemory: sixteenGB), .fine,
          "so is a photo with a few layers")

    // 20000 x 20000 is 1.6 GB a layer, and the compositing buffer doubles it.
    equal(Document.bytesNeeded(width: 20000, height: 20000), 3_200_000_000,
          "one layer plus its composite is 3.2 GB")
    if case .heavy(let bytes) = Document.verdict(width: 20000, height: 20000, physicalMemory: sixteenGB) {
        equal(bytes, 3_200_000_000, "a 20k canvas warns rather than refuses on 16 GB")
    } else {
        check(false, "20k on 16 GB should warn")
    }

    // The same canvas on a smaller machine is refused outright.
    if case .tooLarge = Document.verdict(width: 20000, height: 20000, physicalMemory: 4_000_000_000) {
        check(true, "refused on a 4 GB machine")
    } else {
        check(false, "20k on 4 GB should be refused")
    }

    // Layers multiply it, so the check counts them.
    if case .tooLarge = Document.verdict(width: 20000, height: 20000, layers: 6,
                                         physicalMemory: sixteenGB) {
        check(true, "six layers at 20k is refused even on 16 GB")
    } else {
        check(false, "layer count should count against the limit")
    }

    // Absurd dimensions are rejected before any arithmetic about memory.
    if case .tooLarge(let reason) = Document.verdict(width: 100_000, height: 10,
                                                     physicalMemory: sixteenGB) {
        check(reason.contains("32000"), "a side beyond the bitmap limit is named as the reason")
    } else {
        check(false, "100k wide should be refused")
    }
    if case .tooLarge = Document.verdict(width: 0, height: 100, physicalMemory: sixteenGB) {
        check(true, "zero width is refused")
    } else {
        check(false, "zero width should be refused")
    }
}

section("compositing only what is on screen")
do {
    let doc = Document(width: 2000, height: 1500, background: nil)
    let layer = doc.selectedLayer!
    layer.context.setFillColor(NSColor.red.cgColor)
    layer.context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))       // bottom left
    layer.context.setFillColor(NSColor.blue.cgColor)
    layer.context.fill(CGRect(x: 1800, y: 1300, width: 200, height: 200)) // top right

    // A slice comes back at the pixel size asked for, not the canvas size.
    let slice = doc.composite(region: CGRect(x: 0, y: 0, width: 400, height: 300),
                              pixelSize: CGSize(width: 400, height: 300))
    equal(slice?.width ?? 0, 400, "the buffer is the size requested")
    equal(slice?.height ?? 0, 300, "in both axes")

    let probe = Layer(width: slice!.width, height: slice!.height, name: "probe")
    probe.draw(image: slice!)
    equal(PixelOps.sample(probe, x: 50, y: 50)?.r ?? 0, 255, "the red corner is in this slice")
    check(Int(PixelOps.sample(probe, x: 50, y: 50)?.b ?? 255) < 60, "and it is red")
    check(Int(PixelOps.sample(probe, x: 380, y: 280)?.a ?? 255) < 60, "the rest of the slice is empty")

    // Zoomed out, the buffer is smaller than the region it covers.
    let thumb = doc.composite(region: doc.bounds, pixelSize: CGSize(width: 200, height: 150))
    equal(thumb?.width ?? 0, 200, "a zoomed-out view costs 200 pixels across")
    let thumbProbe = Layer(width: thumb!.width, height: thumb!.height, name: "thumb")
    thumbProbe.draw(image: thumb!)
    equal(PixelOps.sample(thumbProbe, x: 5, y: 5)?.r ?? 0, 255, "red still bottom left")
    equal(PixelOps.sample(thumbProbe, x: 195, y: 145)?.b ?? 0, 255, "blue still top right")

    check(doc.composite(region: CGRect(x: 5000, y: 5000, width: 10, height: 10),
                        pixelSize: CGSize(width: 10, height: 10)) == nil,
          "a region off the canvas composites to nothing")
}

section("history stays inside a memory budget")
do {
    let doc = Document(width: 1000, height: 1000)
    // A budget of three snapshots' worth: 1000 x 1000 x 4 = 4 MB each.
    doc.history.byteBudget = 12_000_000

    for step in 1...10 {
        doc.selectedLayer?.context.setFillColor(NSColor.black.cgColor)
        doc.selectedLayer?.context.fill(CGRect(x: step * 10, y: 0, width: 8, height: 1000))
        doc.commit("stroke \(step)")
    }

    check(doc.history.entries.count < 10, "old steps are dropped once the budget is passed")
    check(doc.history.estimatedBytes <= 12_000_000, "the kept steps fit the budget")
    check(doc.history.canUndo, "there is still something to undo")
    check(doc.undo(), "and undo still works")

    // A small document keeps its full history.
    let small = Document(width: 100, height: 100)
    for step in 1...10 { small.addLayer(named: "layer \(step)") }
    equal(small.history.entries.count, 11, "a small document keeps every step")
}

// MARK: - Combining selections

section("modifiers combine selections")
do {
    let doc = Document(width: 100, height: 100)
    let settings = ToolSettings()
    settings.tool = .rectangleSelect
    let engine = ToolEngine(doc: doc, settings: settings)

    func dragSelect(_ from: CGPoint, _ to: CGPoint, _ modifiers: NSEvent.ModifierFlags = []) {
        engine.mouseDown(at: from, rightButton: false, modifiers: modifiers)
        engine.mouseDragged(to: to, modifiers: modifiers)
        engine.mouseUp(at: to, modifiers: modifiers)
    }
    func selected(_ x: CGFloat, _ y: CGFloat) -> Bool {
        doc.selectionPath?.contains(CGPoint(x: x, y: y)) ?? false
    }

    // A plain drag replaces whatever was selected.
    dragSelect(CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 30))
    dragSelect(CGPoint(x: 60, y: 60), CGPoint(x: 80, y: 80))
    check(!selected(20, 20), "a second plain drag drops the first region")
    check(selected(70, 70), "the newest region is selected")

    // Option adds a second region without losing the first.
    dragSelect(CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 30))
    dragSelect(CGPoint(x: 60, y: 60), CGPoint(x: 80, y: 80), [.option])
    check(selected(20, 20), "the first region survives")
    check(selected(70, 70), "the second region is added")
    check(!selected(45, 45), "the gap between them is not selected")

    // A third region joins the other two.
    dragSelect(CGPoint(x: 10, y: 60), CGPoint(x: 30, y: 80), [.option])
    check(selected(20, 20) && selected(70, 70) && selected(20, 70), "three regions at once")

    // Command subtracts.
    doc.selectionPath = CGPath(rect: CGRect(x: 0, y: 0, width: 100, height: 100), transform: nil)
    dragSelect(CGPoint(x: 40, y: 40), CGPoint(x: 60, y: 60), [.command])
    check(selected(10, 10), "the untouched part stays")
    check(!selected(50, 50), "the dragged part is removed")

    // Option and command together intersect.
    doc.selectionPath = CGPath(rect: CGRect(x: 0, y: 0, width: 50, height: 50), transform: nil)
    dragSelect(CGPoint(x: 25, y: 25), CGPoint(x: 100, y: 100), [.option, .command])
    check(selected(35, 35), "the overlap stays")
    check(!selected(10, 10), "the rest of the old selection goes")
    check(!selected(70, 70), "the rest of the new region goes")

    // The magic wand honours the same modifiers.
    let wandDoc = Document(width: 40, height: 20)
    wandDoc.selectedLayer?.context.setFillColor(NSColor.black.cgColor)
    wandDoc.selectedLayer?.context.fill(CGRect(x: 0, y: 0, width: 10, height: 20))
    wandDoc.selectedLayer?.context.setFillColor(NSColor.blue.cgColor)
    wandDoc.selectedLayer?.context.fill(CGRect(x: 30, y: 0, width: 10, height: 20))
    let wandSettings = ToolSettings()
    wandSettings.tool = .magicWand
    wandSettings.tolerance = 0.05
    let wand = ToolEngine(doc: wandDoc, settings: wandSettings)

    wand.mouseDown(at: CGPoint(x: 5, y: 10), rightButton: false, modifiers: [])
    wand.mouseUp(at: CGPoint(x: 5, y: 10), modifiers: [])
    wand.mouseDown(at: CGPoint(x: 35, y: 10), rightButton: false, modifiers: [.option])
    wand.mouseUp(at: CGPoint(x: 35, y: 10), modifiers: [.option])
    let box = wandDoc.selectionPath?.boundingBoxOfPath ?? .zero
    near(box.minX, 0, 1, "the wand kept the black region")
    near(box.maxX, 40, 1, "and added the blue one")
    check(!(wandDoc.selectionPath?.contains(CGPoint(x: 20, y: 10)) ?? true),
          "the white gap between them stays unselected")
}

section("clicking clears the selection")
do {
    let doc = Document(width: 50, height: 50)
    let settings = ToolSettings()
    settings.tool = .rectangleSelect
    let engine = ToolEngine(doc: doc, settings: settings)

    func click(_ at: CGPoint, _ modifiers: NSEvent.ModifierFlags = []) {
        engine.mouseDown(at: at, rightButton: false, modifiers: modifiers)
        engine.mouseUp(at: at, modifiers: modifiers)
    }

    doc.selectionPath = CGPath(rect: CGRect(x: 5, y: 5, width: 20, height: 20), transform: nil)
    click(CGPoint(x: 40, y: 40))
    check(doc.selectionPath == nil, "a click with no drag deselects")

    // The same for the other selection tools.
    doc.selectionPath = CGPath(rect: CGRect(x: 5, y: 5, width: 20, height: 20), transform: nil)
    settings.tool = .ellipseSelect
    click(CGPoint(x: 30, y: 30))
    check(doc.selectionPath == nil, "the ellipse tool deselects too")

    doc.selectionPath = CGPath(rect: CGRect(x: 5, y: 5, width: 20, height: 20), transform: nil)
    settings.tool = .lassoSelect
    click(CGPoint(x: 12, y: 34))
    check(doc.selectionPath == nil, "so does the lasso")

    // Holding a combining modifier means "keep what I have", so a stray click
    // must not throw the selection away.
    settings.tool = .rectangleSelect
    let kept = CGPath(rect: CGRect(x: 5, y: 5, width: 20, height: 20), transform: nil)
    doc.selectionPath = kept
    click(CGPoint(x: 40, y: 40), [.option])
    equal(doc.selectionPath?.boundingBoxOfPath ?? .zero, kept.boundingBoxOfPath,
          "option-clicking leaves the selection alone")

    // A real drag still selects, however small.
    engine.mouseDown(at: CGPoint(x: 10, y: 10), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 14, y: 13), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 14, y: 13), modifiers: [])
    equal(doc.selectionPath?.boundingBoxOfPath ?? .zero, CGRect(x: 10, y: 10, width: 4, height: 3),
          "a small drag still selects")
}

section("a replacing drag drops the old selection at once")
do {
    let doc = Document(width: 50, height: 50)
    doc.selectionPath = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)
    let settings = ToolSettings()
    settings.tool = .rectangleSelect
    let engine = ToolEngine(doc: doc, settings: settings)

    engine.mouseDown(at: CGPoint(x: 30, y: 30), rightButton: false, modifiers: [])
    check(doc.selectionPath == nil, "the old selection goes on mouse down, not on mouse up")
    engine.mouseDragged(to: CGPoint(x: 40, y: 40), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 40, y: 40), modifiers: [])
    equal(doc.selectionPath?.boundingBoxOfPath ?? .zero, CGRect(x: 30, y: 30, width: 10, height: 10),
          "the new region replaces it")

    // Holding option keeps the old selection on screen while dragging.
    doc.selectionPath = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)
    engine.mouseDown(at: CGPoint(x: 30, y: 30), rightButton: false, modifiers: [.option])
    check(doc.selectionPath != nil, "adding to a selection keeps it visible")
    engine.mouseUp(at: CGPoint(x: 30, y: 30), modifiers: [.option])
}

// MARK: - Resize anchors

section("canvas size anchor")
do {
    // A 10x10 red square that we grow to 30x30 from various anchors.
    func grown(from anchor: CGPoint) -> Document {
        let doc = Document(width: 10, height: 10, background: nil)
        doc.selectedLayer?.fill(with: .red)
        doc.resizeCanvas(to: CGSize(width: 30, height: 30), anchor: anchor)
        return doc
    }
    func opaque(_ doc: Document, _ x: Int, _ y: Int) -> Bool {
        (pixel(doc, x, y)?.a ?? 0) > 200
    }

    // Top-left cell: image keeps the top-left corner, space is added right and below.
    let topLeft = grown(from: CGPoint(x: 0, y: 1))
    check(opaque(topLeft, 5, 25), "top-left anchor keeps the image at the top-left")
    check(!opaque(topLeft, 25, 5), "the opposite corner is empty")

    let bottomRight = grown(from: CGPoint(x: 1, y: 0))
    check(opaque(bottomRight, 25, 5), "bottom-right anchor keeps the image at the bottom-right")
    check(!opaque(bottomRight, 5, 25), "the opposite corner is empty")

    let centered = grown(from: CGPoint(x: 0.5, y: 0.5))
    check(opaque(centered, 15, 15), "center anchor keeps the image in the middle")
    check(!opaque(centered, 2, 2), "corners are empty when centered")
    check(!opaque(centered, 28, 28), "far corner is empty when centered")

    equal(centered.width, 30, "canvas took the new width")
    equal(centered.history.currentTitle, "Canvas Size", "one history step")
}

section("crop to selection")
do {
    let doc = Document(width: 20, height: 20, background: nil)
    doc.selectedLayer?.fill(with: .red)
    doc.commit("Fill")
    doc.selectionPath = CGPath(rect: CGRect(x: 4, y: 6, width: 8, height: 5), transform: nil)
    doc.crop(to: doc.selectionPath!.boundingBoxOfPath)

    equal(doc.width, 8, "crop takes the selection width")
    equal(doc.height, 5, "crop takes the selection height")
    check(doc.selectionPath == nil, "and drops the selection it cropped to")

    // The whole point: a crop is an edit, not a new document.
    equal(doc.history.currentTitle, "Crop to Selection", "crop lands in history")
    check(doc.history.canUndo, "so it can be undone")
    doc.undo()
    equal(doc.width, 20, "undo brings the canvas back")
    equal(doc.height, 20, "at its full height")
    check((pixel(doc, 18, 18)?.a ?? 0) > 200, "with the pixels the crop threw away")
}

section("image size anchor")
do {
    // A wide image resized into a square box keeps its shape when fitting.
    func fitted(anchor: CGPoint) -> Document {
        let doc = Document(width: 40, height: 20, background: nil)
        doc.selectedLayer?.fill(with: .red)
        doc.resizeImage(to: CGSize(width: 40, height: 40), anchor: anchor, fit: true)
        return doc
    }
    func opaque(_ doc: Document, _ x: Int, _ y: Int) -> Bool {
        (pixel(doc, x, y)?.a ?? 0) > 200
    }

    let top = fitted(anchor: CGPoint(x: 0.5, y: 1))
    check(opaque(top, 20, 35), "fitting to the top leaves the image up there")
    check(!opaque(top, 20, 5), "the bottom is padded")

    let bottom = fitted(anchor: CGPoint(x: 0.5, y: 0))
    check(opaque(bottom, 20, 5), "fitting to the bottom moves it down")
    check(!opaque(bottom, 20, 35), "the top is padded")

    // Stretching ignores the anchor and fills the whole canvas.
    let stretched = Document(width: 40, height: 20, background: nil)
    stretched.selectedLayer?.fill(with: .red)
    stretched.resizeImage(to: CGSize(width: 40, height: 40), anchor: CGPoint(x: 0, y: 1), fit: false)
    check(opaque(stretched, 20, 5) && opaque(stretched, 20, 35), "stretching fills the new size")
    equal(stretched.history.currentTitle, "Image Size", "one history step")
}

// MARK: - Selection move and resize

section("move selection tool")
do {
    let doc = Document(width: 100, height: 100)
    doc.selectionPath = CGPath(rect: CGRect(x: 20, y: 20, width: 40, height: 40), transform: nil)
    let settings = ToolSettings()
    settings.tool = .moveSelection
    let engine = ToolEngine(doc: doc, settings: settings)

    // Dragging the interior moves the outline.
    engine.mouseDown(at: CGPoint(x: 40, y: 40), rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 55, y: 30), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 55, y: 30), modifiers: [])
    var box = doc.selectionPath?.boundingBoxOfPath ?? .zero
    near(box.minX, 35, 0.5, "selection moved right")
    near(box.minY, 10, 0.5, "selection moved down")
    near(box.width, 40, 0.5, "moving does not resize")

    // Dragging the top-right corner handle resizes it.
    doc.selectionPath = CGPath(rect: CGRect(x: 20, y: 20, width: 40, height: 40), transform: nil)
    let corner = engine.selectionHandles()[4]
    near(corner.x, 60, 0.5, "corner handle sits on the box")
    engine.mouseDown(at: corner, rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 80, y: 100), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 80, y: 100), modifiers: [])
    box = doc.selectionPath?.boundingBoxOfPath ?? .zero
    near(box.minX, 20, 0.5, "the far edge stays put")
    near(box.minY, 20, 0.5, "the far edge stays put vertically")
    near(box.width, 60, 0.5, "width follows the handle")
    near(box.height, 80, 0.5, "height follows the handle")
    equal(doc.history.currentTitle, "Resize Selection", "resizing is its own history step")

    // An ellipse keeps its shape while being scaled.
    doc.selectionPath = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 20, height: 20), transform: nil)
    let edge = engine.selectionHandles()[3]
    engine.mouseDown(at: edge, rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 40, y: 10), modifiers: [])
    engine.mouseUp(at: CGPoint(x: 40, y: 10), modifiers: [])
    box = doc.selectionPath?.boundingBoxOfPath ?? .zero
    near(box.width, 40, 0.5, "the ellipse widened")
    near(box.height, 20, 0.5, "the untouched axis is unchanged")
    check(!(doc.selectionPath?.contains(CGPoint(x: 1, y: 19)) ?? true), "corners stay outside the ellipse")

    // Shift keeps the proportions.
    doc.selectionPath = CGPath(rect: CGRect(x: 0, y: 0, width: 20, height: 40), transform: nil)
    let grow = engine.selectionHandles()[4]
    engine.mouseDown(at: grow, rightButton: false, modifiers: [])
    engine.mouseDragged(to: CGPoint(x: 40, y: 50), modifiers: [.shift])
    engine.mouseUp(at: CGPoint(x: 40, y: 50), modifiers: [.shift])
    box = doc.selectionPath?.boundingBoxOfPath ?? .zero
    near(box.width / box.height, 0.5, 0.01, "shift preserves the aspect ratio")
}

section("paste selects what was pasted")
do {
    let doc = Document(width: 60, height: 60)
    let stamp = Layer(width: 10, height: 8, name: "clip")
    stamp.fill(with: .red)

    let pasted = doc.paste(stamp.image!)
    equal(pasted?.width ?? 0, 10, "pasted at its own size")
    equal(pasted?.origin.y ?? -1, 52, "lands in the top-left corner")

    let box = doc.selectionPath?.boundingBoxOfPath ?? .zero
    equal(box, pasted ?? .zero, "the pasted region becomes the selection")
    equal(doc.history.currentTitle, "Paste", "paste is one history step")
    equal(pixel(doc, 5, 55)?.r ?? 0, 255, "the pixels landed")

    // Pasting again with a selection lands on that selection.
    doc.selectionPath = CGPath(rect: CGRect(x: 20, y: 20, width: 30, height: 30), transform: nil)
    let second = doc.paste(stamp.image!)
    equal(second?.origin.x ?? -1, 20, "reuses the selection's left edge")
    equal(second?.origin.y ?? -1, 42, "aligns to the selection's top edge")
    equal(doc.selectionPath?.boundingBoxOfPath ?? .zero, second ?? .zero, "selection follows the new paste")
}

// MARK: - Color entry

section("hex parsing and formatting")
do {
    equal(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1).hexString, "FF8000", "opaque color is six digits")
    equal(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5).hexString, "00000080", "alpha appends two digits")

    let long = NSColor.fromHex("#1E90FF")
    equal(long?.rgbaBytes.r ?? -1, 30, "leading # is ignored")
    equal(long?.rgbaBytes.g ?? -1, 144, "green parsed")
    equal(long?.rgbaBytes.b ?? -1, 255, "blue parsed")
    equal(long?.rgbaBytes.a ?? -1, 255, "no alpha means opaque")

    let short = NSColor.fromHex("f80")
    equal(short?.hexString ?? "", "FF8800", "shorthand expands")

    let withAlpha = NSColor.fromHex("FF000080")
    equal(withAlpha?.rgbaBytes.a ?? -1, 128, "eight digits carry alpha")

    check(NSColor.fromHex("nothex") == nil, "letters outside hex are rejected")
    check(NSColor.fromHex("FFFF") != nil, "four digits are RGBA shorthand")
    check(NSColor.fromHex("FFFFF") == nil, "five digits are not a color")
    check(NSColor.fromHex("") == nil, "empty text is not a color")

    // Round trip through the hex string.
    let original = NSColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 0.75)
    let restored = NSColor.fromHex(original.hexString)
    equal(restored?.hexString ?? "", original.hexString, "hex survives a round trip")
}

section("rgba and hsv entry")
do {
    let color = NSColor.fromBytes(r: 300, g: -20, b: 128, a: 200)
    equal(color.rgbaBytes.r, 255, "high values clamp")
    equal(color.rgbaBytes.g, 0, "negative values clamp")
    equal(color.rgbaBytes.b, 128, "in-range values pass through")
    equal(color.rgbaBytes.a, 200, "alpha passes through")

    let red = NSColor.fromBytes(r: 255, g: 0, b: 0, a: 255)
    let hsv = red.hsvValues
    equal(hsv.h, 0, "red sits at hue 0")
    equal(hsv.s, 100, "red is fully saturated")
    equal(hsv.v, 100, "red is full value")

    let fromHSV = NSColor.fromHSV(h: 120, s: 100, v: 100)
    equal(fromHSV.hexString, "00FF00", "hue 120 is green")
    // 999 wraps to hue 279, saturation and value clamp to 100%.
    equal(NSColor.fromHSV(h: 999, s: 999, v: 999).hexString, "A600FF", "out-of-range HSV wraps and clamps")
}

print(failures == 0
      ? "\nAll \(checks) checks passed."
      : "\n\(failures) of \(checks) checks failed.")
exit(failures == 0 ? 0 : 1)
