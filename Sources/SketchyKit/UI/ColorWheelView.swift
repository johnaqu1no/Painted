import AppKit

/// HSV wheel: hue around the circumference, saturation along the radius.
final class ColorWheelView: NSView {
    /// The wheel itself is always drawn at full brightness, the way the macOS
    /// color wheel behaves; the panel's value slider dims the picked color.
    var brightness: CGFloat = 1.0 { didSet { needsDisplay = true } }
    var selection: NSColor = .black { didSet { needsDisplay = true } }
    var onPick: ((NSColor) -> Void)?

    private var cache: CGImage?

    override var isFlipped: Bool { false }

    private func wheelImage(size: CGSize) -> CGImage? {
        if let cache, cache.width == Int(size.width) { return cache }
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let cx = CGFloat(w) / 2, cy = CGFloat(h) / 2
        let radius = min(cx, cy)
        for y in 0..<h {
            for x in 0..<w {
                let dx = CGFloat(x) - cx + 0.5, dy = CGFloat(y) - cy + 0.5
                let dist = hypot(dx, dy)
                let o = (y * w + x) * 4
                guard dist <= radius else { continue }
                let hue = (atan2(-dy, dx) / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
                let sat = min(1, dist / radius)
                let c = NSColor.fromHSV(h: Int(hue * 360), s: Int(sat * 100), v: 100)
                // Feather the rim so the circle isn't jagged.
                let alpha = min(1, (radius - dist))
                pixels[o + 0] = UInt8(c.redComponent * 255 * alpha)
                pixels[o + 1] = UInt8(c.greenComponent * 255 * alpha)
                pixels[o + 2] = UInt8(c.blueComponent * 255 * alpha)
                pixels[o + 3] = UInt8(alpha * 255)
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        cache = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                        bytesPerRow: w * 4, space: cs,
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        return cache
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let side = min(bounds.width, bounds.height)
        let rect = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        let scale = window?.backingScaleFactor ?? 2
        if let img = wheelImage(size: CGSize(width: side * scale, height: side * scale)) {
            ctx.draw(img, in: rect)
        }
        let c = selection.usingColorSpace(.deviceRGB) ?? .black
        let radius = side / 2
        let angle = c.hueComponent * 2 * .pi
        let dist = c.saturationComponent * radius
        let pt = CGPoint(x: rect.midX + cos(angle) * dist, y: rect.midY + sin(angle) * dist)
        ctx.setLineWidth(1.5)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.strokeEllipse(in: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10))
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.strokeEllipse(in: CGRect(x: pt.x - 6.5, y: pt.y - 6.5, width: 13, height: 13))
    }

    override func mouseDown(with event: NSEvent) { pick(event) }
    override func mouseDragged(with event: NSEvent) { pick(event) }

    private func pick(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let side = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dx = p.x - center.x, dy = p.y - center.y
        let radius = side / 2
        let hue = (atan2(dy, dx) / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
        let sat = min(1, hypot(dx, dy) / radius)
        // `brightness` mirrors the panel slider so picking respects the value.
        let color = NSColor.fromHSV(h: Int((hue * 360).rounded()),
                                    s: Int((sat * 100).rounded()),
                                    v: Int((brightness * 100).rounded()))
        selection = color
        onPick?(color)
    }
}
