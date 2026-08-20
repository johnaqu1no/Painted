import AppKit
import CoreGraphics

/// A single raster layer. Pixels live in a premultiplied BGRA8 bitmap context
/// so tools can both draw with Core Graphics and poke individual pixels.
final class Layer {
    let width: Int
    let height: Int
    var name: String
    var isVisible: Bool = true
    var opacity: CGFloat = 1.0
    var blendMode: LayerBlendMode = .normal

    private(set) var context: CGContext

    init(width: Int, height: Int, name: String) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.name = name
        self.context = Layer.makeContext(width: self.width, height: self.height)
    }

    static func makeContext(width: Int, height: Int) -> CGContext {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: width * 4,
                                  space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else {
            fatalError("Could not allocate a \(width)x\(height) bitmap")
        }
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        return ctx
    }

    var image: CGImage? { context.makeImage() }

    /// Raw pixel access (BGRA order, premultiplied).
    var data: UnsafeMutablePointer<UInt8>? {
        context.data?.assumingMemoryBound(to: UInt8.self)
    }

    var bytesPerRow: Int { context.bytesPerRow }

    func clear() {
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    }

    func fill(with color: NSColor) {
        context.saveGState()
        context.setBlendMode(.copy)
        context.setFillColor(color.srgb.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()
    }

    func draw(image img: CGImage, in rect: CGRect? = nil) {
        let r = rect ?? CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(img, in: r)
    }

    /// Replace the whole bitmap with a snapshot (used by undo).
    func restore(from snapshot: CGImage?) {
        clear()
        if let snapshot { context.draw(snapshot, in: CGRect(x: 0, y: 0, width: width, height: height)) }
    }

    func copyLayer(named newName: String? = nil) -> Layer {
        let l = Layer(width: width, height: height, name: newName ?? "\(name) copy")
        if let img = image { l.draw(image: img) }
        l.isVisible = isVisible
        l.opacity = opacity
        l.blendMode = blendMode
        return l
    }

    func thumbnail(size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        drawCheckerboard(in: NSRect(origin: .zero, size: size), cell: 4)
        if let cg = image {
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.draw(in: NSRect(origin: .zero, size: size),
                     from: .zero,
                     operation: .sourceOver,
                     fraction: 1,
                     respectFlipped: true,
                     hints: nil)
        }
        img.unlockFocus()
        return img
    }
}

func drawCheckerboard(in rect: NSRect, cell: CGFloat) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    ctx.clip(to: rect)
    ctx.setFillColor(NSColor(white: 0.80, alpha: 1).cgColor)
    ctx.fill(rect)
    ctx.setFillColor(NSColor(white: 0.62, alpha: 1).cgColor)
    var y = rect.minY
    var row = 0
    while y < rect.maxY {
        var x = rect.minX + (row % 2 == 0 ? 0 : cell)
        while x < rect.maxX {
            ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
            x += cell * 2
        }
        y += cell
        row += 1
    }
    ctx.restoreGState()
}
