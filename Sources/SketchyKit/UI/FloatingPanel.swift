import AppKit

/// Small dark utility panel used for Tools / Colors / History / Layers,
/// matching Paint.NET's floating windows.
class FloatingPanel: NSPanel, NSWindowDelegate {
    init(title: String, size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel, .hudWindow],
                   backing: .buffered, defer: false)
        self.title = title
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        collectionBehavior.insert(.fullScreenAuxiliary)
        styleMask.insert(.resizable)
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        delegate = self
    }

    /// Whether the palette sits above the document window at all times.
    /// Off by default: a palette pinned in front covers the canvas, and
    /// clicking the canvas should be enough to bring it forward.
    var keepsInFront: Bool = false {
        didSet {
            isFloatingPanel = keepsInFront
            level = keepsInFront ? .floating : .normal
        }
    }

    override var canBecomeKey: Bool { true }

    /// Palette bodies know how tall they need to be at a given width; never let
    /// the panel shrink below that and clip its controls.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let content = contentView as? PaletteContent,
              let needed = content.preferredHeight(forWidth: frameSize.width) else { return frameSize }
        let chrome = frame.height - contentLayoutRect.height
        return NSSize(width: frameSize.width, height: max(frameSize.height, needed + chrome))
    }

    /// Grows the panel if its content has outgrown a remembered frame.
    func fitContent() {
        guard let content = contentView as? PaletteContent,
              let needed = content.preferredHeight(forWidth: contentLayoutRect.width),
              contentLayoutRect.height < needed else { return }
        setContentSize(NSSize(width: contentLayoutRect.width, height: needed))
    }

    func toggle() {
        if isVisible { orderOut(nil) } else { orderFront(nil) }
    }
}

/// Shared look for the small square icon buttons in the palettes.
final class IconButton: NSButton {
    var isSelectedTool: Bool = false {
        didSet { needsDisplay = true }
    }

    init(symbol: String, tooltip: String, target: AnyObject?, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 26))
        self.target = target
        self.action = action
        bezelStyle = .smallSquare
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 5
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        toolTip = tooltip
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(cfg)
        contentTintColor = .labelColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if isSelectedTool {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
        contentTintColor = isSelectedTool ? .white : .labelColor
        super.draw(dirtyRect)
    }
}
