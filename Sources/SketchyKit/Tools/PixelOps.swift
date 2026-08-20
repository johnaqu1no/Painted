import AppKit
import CoreGraphics

/// Direct pixel work: sampling, flood fill, magic-wand masks.
/// Buffers are premultiplied BGRA8; memory row 0 is the *top* row, while
/// Core Graphics user space has its origin at the bottom left, so every
/// helper converts with `row = height - 1 - y`.
enum PixelOps {

    struct RGBA { var r: UInt8; var g: UInt8; var b: UInt8; var a: UInt8 }

    static func sample(_ layer: Layer, x: Int, y: Int) -> RGBA? {
        guard let d = layer.data, x >= 0, y >= 0, x < layer.width, y < layer.height else { return nil }
        let row = layer.height - 1 - y
        let o = row * layer.bytesPerRow + x * 4
        let a = d[o + 3]
        // Un-premultiply so the picked color matches what the user sees.
        func un(_ c: UInt8) -> UInt8 {
            guard a > 0 else { return 0 }
            return UInt8(min(255, Int(c) * 255 / Int(a)))
        }
        return RGBA(r: un(d[o + 2]), g: un(d[o + 1]), b: un(d[o + 0]), a: a)
    }

    static func color(from p: RGBA) -> NSColor {
        NSColor(srgbRed: CGFloat(p.r) / 255, green: CGFloat(p.g) / 255,
                blue: CGFloat(p.b) / 255, alpha: CGFloat(p.a) / 255)
    }

    /// Builds a boolean mask of pixels matching the seed color.
    /// `contiguous == false` scans the whole layer instead of flooding.
    static func mask(in layer: Layer,
                     seedX: Int, seedY: Int,
                     tolerance: CGFloat,
                     contiguous: Bool) -> [Bool]? {
        guard let d = layer.data else { return nil }
        let w = layer.width, h = layer.height, stride = layer.bytesPerRow
        guard seedX >= 0, seedY >= 0, seedX < w, seedY < h else { return nil }

        func px(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
            let o = (h - 1 - y) * stride + x * 4
            return (Int(d[o + 2]), Int(d[o + 1]), Int(d[o + 0]), Int(d[o + 3]))
        }

        let seed = px(seedX, seedY)
        // Tolerance is a fraction of the max possible RGBA distance.
        let limit = Int(tolerance * 255.0 * 4)

        func matches(_ x: Int, _ y: Int) -> Bool {
            let c = px(x, y)
            let dist = abs(c.0 - seed.0) + abs(c.1 - seed.1) + abs(c.2 - seed.2) + abs(c.3 - seed.3)
            return dist <= limit
        }

        var mask = [Bool](repeating: false, count: w * h)

        if !contiguous {
            for y in 0..<h {
                for x in 0..<w where matches(x, y) { mask[y * w + x] = true }
            }
            return mask
        }

        // Scanline flood fill.
        var stack: [(Int, Int)] = [(seedX, seedY)]
        while let (sx, sy) = stack.popLast() {
            var x1 = sx
            while x1 >= 0 && !mask[sy * w + x1] && matches(x1, sy) { x1 -= 1 }
            x1 += 1
            var spanAbove = false, spanBelow = false
            var x = x1
            while x < w && !mask[sy * w + x] && matches(x, sy) {
                mask[sy * w + x] = true
                if sy > 0 {
                    let above = !mask[(sy - 1) * w + x] && matches(x, sy - 1)
                    if above && !spanAbove { stack.append((x, sy - 1)); spanAbove = true }
                    else if !above { spanAbove = false }
                }
                if sy < h - 1 {
                    let below = !mask[(sy + 1) * w + x] && matches(x, sy + 1)
                    if below && !spanBelow { stack.append((x, sy + 1)); spanBelow = true }
                    else if !below { spanBelow = false }
                }
                x += 1
            }
        }
        return mask
    }

    /// Traces the outline of a mask as closed loops, in Core Graphics
    /// coordinates. One rectangle per row would clip correctly but stroke every
    /// internal row edge, which turns marching ants into a hatch pattern, so the
    /// boundary is walked instead: outer loops and holes both come out closed,
    /// and an even-odd fill treats them correctly.
    static func path(from mask: [Bool], width w: Int, height h: Int) -> CGPath {
        func inMask(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x]
        }

        // Boundary edges, wound so that each one leads into the next.
        var next: [Int: [Int]] = [:]
        func corner(_ x: Int, _ y: Int) -> Int { y * (w + 1) + x }
        func addEdge(_ from: (Int, Int), _ to: (Int, Int)) {
            next[corner(from.0, from.1), default: []].append(corner(to.0, to.1))
        }

        for y in 0..<h {
            for x in 0..<w where mask[y * w + x] {
                if !inMask(x, y - 1) { addEdge((x, y), (x + 1, y)) }
                if !inMask(x + 1, y) { addEdge((x + 1, y), (x + 1, y + 1)) }
                if !inMask(x, y + 1) { addEdge((x + 1, y + 1), (x, y + 1)) }
                if !inMask(x - 1, y) { addEdge((x, y + 1), (x, y)) }
            }
        }

        let path = CGMutablePath()
        while let start = next.first(where: { !$0.value.isEmpty })?.key {
            var loop: [Int] = [start]
            var current = start
            // Follow edges until the walk returns to where it began.
            while var outgoing = next[current], !outgoing.isEmpty {
                let step = outgoing.removeLast()
                next[current] = outgoing
                if outgoing.isEmpty { next[current] = nil }
                current = step
                if current == start { break }
                loop.append(current)
            }
            guard loop.count > 2 else { continue }
            let corners = collapseCollinear(loop.map { point($0, width: w) })
            path.move(to: corners[0])
            for index in 1..<corners.count { path.addLine(to: corners[index]) }
            path.closeSubpath()
        }
        return path.copy() ?? path
    }

    /// Drops the points in the middle of a straight run, so a rectangular
    /// region ends up with four corners rather than one point per pixel edge.
    private static func collapseCollinear(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var result: [CGPoint] = []
        for (index, current) in points.enumerated() {
            let previous = points[(index + points.count - 1) % points.count]
            let following = points[(index + 1) % points.count]
            let turns = (current.x - previous.x) != (following.x - current.x)
                || (current.y - previous.y) != (following.y - current.y)
            if turns { result.append(current) }
        }
        return result.count > 2 ? result : points
    }

    private static func point(_ corner: Int, width w: Int) -> CGPoint {
        CGPoint(x: CGFloat(corner % (w + 1)), y: CGFloat(corner / (w + 1)))
    }

    /// Paint-bucket fill honoring tolerance, contiguity and an optional clip.
    static func floodFill(layer: Layer,
                          seedX: Int, seedY: Int,
                          color: NSColor,
                          tolerance: CGFloat,
                          contiguous: Bool,
                          clip: CGPath?,
                          blend: CGBlendMode = .normal,
                          alpha: CGFloat = 1.0) {
        guard let mask = mask(in: layer, seedX: seedX, seedY: seedY,
                              tolerance: tolerance, contiguous: contiguous) else { return }
        let region = path(from: mask, width: layer.width, height: layer.height)
        let ctx = layer.context
        ctx.saveGState()
        if let clip { ctx.addPath(clip); ctx.clip(using: .evenOdd) }
        ctx.addPath(region)
        ctx.clip()
        ctx.setAlpha(alpha)
        ctx.setBlendMode(blend)
        ctx.setFillColor(color.srgb.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: layer.width, height: layer.height))
        ctx.restoreGState()
    }

    /// Replaces pixels close to `from` with `to` inside the brush dab — the Recolor tool.
    static func recolor(layer: Layer,
                        in rect: CGRect,
                        from source: NSColor,
                        to target: NSColor,
                        tolerance: CGFloat) {
        guard let d = layer.data else { return }
        let w = layer.width, h = layer.height, stride = layer.bytesPerRow
        let s = source.srgb
        let t = target.srgb
        let sr = Int(s.redComponent * 255), sg = Int(s.greenComponent * 255), sb = Int(s.blueComponent * 255)
        let tr = UInt8(t.redComponent * 255), tg = UInt8(t.greenComponent * 255), tb = UInt8(t.blueComponent * 255)
        let limit = Int(tolerance * 255 * 3)

        let x0 = max(0, Int(rect.minX)), x1 = min(w - 1, Int(rect.maxX))
        let y0 = max(0, Int(rect.minY)), y1 = min(h - 1, Int(rect.maxY))
        guard x0 <= x1, y0 <= y1 else { return }

        for y in y0...y1 {
            let row = (h - 1 - y) * stride
            for x in x0...x1 {
                let o = row + x * 4
                let a = Int(d[o + 3])
                guard a > 0 else { continue }
                let r = Int(d[o + 2]) * 255 / a
                let g = Int(d[o + 1]) * 255 / a
                let b = Int(d[o + 0]) * 255 / a
                if abs(r - sr) + abs(g - sg) + abs(b - sb) <= limit {
                    d[o + 2] = UInt8(Int(tr) * a / 255)
                    d[o + 1] = UInt8(Int(tg) * a / 255)
                    d[o + 0] = UInt8(Int(tb) * a / 255)
                }
            }
        }
    }
}
