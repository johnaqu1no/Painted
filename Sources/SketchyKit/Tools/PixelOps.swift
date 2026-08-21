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

    /// How far a single channel may drift and still count as the same color.
    ///
    /// Tolerance is how far any single channel may drift; summing the channels
    /// instead lets three small differences add up to a match. The curve keeps
    /// the low end of the slider fine-grained — a straight percentage spends
    /// most of its travel flooding everything.
    static func channelLimit(for tolerance: CGFloat) -> Int {
        let t = tolerance.clamped(to: 0...1)
        return Int((t * t * t * 255).rounded())
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
        let limit = channelLimit(for: tolerance)

        func matches(_ x: Int, _ y: Int) -> Bool {
            let c = px(x, y)
            let dist = max(max(abs(c.0 - seed.0), abs(c.1 - seed.1)),
                           max(abs(c.2 - seed.2), abs(c.3 - seed.3)))
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
        let limit = channelLimit(for: tolerance)

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
                if max(abs(r - sr), max(abs(g - sg), abs(b - sb))) <= limit {
                    d[o + 2] = UInt8(Int(tr) * a / 255)
                    d[o + 1] = UInt8(Int(tg) * a / 255)
                    d[o + 0] = UInt8(Int(tb) * a / 255)
                }
            }
        }
    }
}

// MARK: - Healing

extension PixelOps {

    /// A patch of a layer as straight (un-premultiplied) float channels.
    struct Patch {
        var width: Int
        var height: Int
        /// r, g, b, a per pixel, row 0 at the top, matching the bitmap.
        var samples: [Float]

        subscript(x: Int, y: Int, c: Int) -> Float {
            get { samples[(y * width + x) * 4 + c] }
            set { samples[(y * width + x) * 4 + c] = newValue }
        }
    }

    /// Reads `rect` (image coordinates) out of a layer, repeating the edge
    /// pixels for anything that hangs over the side so a dab still works in a
    /// corner. Returns nil only when the rectangle misses the layer entirely.
    static func readPatch(_ layer: Layer, rect: CGRect) -> Patch? {
        guard let d = layer.data else { return nil }
        let x0 = Int(rect.minX), y0 = Int(rect.minY)
        let w = Int(rect.width), h = Int(rect.height)
        guard w > 0, h > 0,
              rect.intersects(CGRect(x: 0, y: 0, width: layer.width, height: layer.height)) else { return nil }

        var samples = [Float](repeating: 0, count: w * h * 4)
        let stride = layer.bytesPerRow
        for row in 0..<h {
            let y = (y0 + row).clamped(to: 0...(layer.height - 1))
            let src = (layer.height - 1 - y) * stride
            for col in 0..<w {
                let x = (x0 + col).clamped(to: 0...(layer.width - 1))
                let o = src + x * 4
                let a = Float(d[o + 3])
                let scale: Float = a > 0 ? 255 / a : 0
                let base = (row * w + col) * 4
                samples[base + 0] = Float(d[o + 2]) * scale
                samples[base + 1] = Float(d[o + 1]) * scale
                samples[base + 2] = Float(d[o + 0]) * scale
                samples[base + 3] = a
            }
        }
        return Patch(width: w, height: h, samples: samples)
    }

    /// How much a patch varies, used to pick the calmest place to heal from.
    static func variance(_ patch: Patch) -> Float {
        let pixels = patch.width * patch.height
        guard pixels > 0 else { return .greatestFiniteMagnitude }
        var mean: Float = 0
        for i in 0..<pixels {
            mean += (patch.samples[i * 4] + patch.samples[i * 4 + 1] + patch.samples[i * 4 + 2]) / 3
        }
        mean /= Float(pixels)
        var total: Float = 0
        for i in 0..<pixels {
            let v = (patch.samples[i * 4] + patch.samples[i * 4 + 1] + patch.samples[i * 4 + 2]) / 3
            total += (v - mean) * (v - mean)
        }
        return total / Float(pixels)
    }

    /// Heals a round dab: the texture comes from `offset` away, while the
    /// colour and shading are pulled to match the ring of pixels around the
    /// dab. Correcting against the surrounding ring rather than the dab's own
    /// average is what lets a heal wipe out a blemish instead of smearing it —
    /// the blemish never gets a vote on the tone it is replaced with.
    @discardableResult
    static func heal(layer: Layer,
                     at center: CGPoint,
                     diameter: CGFloat,
                     offset: CGSize,
                     hardness: CGFloat,
                     clip: CGPath? = nil) -> Bool {
        let radius = max(1, Int((diameter / 2).rounded()))
        // A margin outside the dab, which is where the tone is read from.
        let margin = max(2, radius / 3)
        let outer = radius + margin
        let side = outer * 2 + 1
        let originX = Int(center.x.rounded()) - outer
        let originY = Int(center.y.rounded()) - outer
        let destRect = CGRect(x: originX, y: originY, width: side, height: side)
        let sourceRect = destRect.offsetBy(dx: offset.width.rounded(), dy: offset.height.rounded())

        guard let dest = readPatch(layer, rect: destRect),
              let source = readPatch(layer, rect: sourceRect),
              let d = layer.data else { return false }

        // Mean of the ring just outside the dab, in both patches.
        var destRing = [Float](repeating: 0, count: 4)
        var sourceRing = [Float](repeating: 0, count: 4)
        var ringCount: Float = 0
        for row in 0..<side {
            for col in 0..<side {
                let dx = Float(col - outer), dy = Float(row - outer)
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance > Float(radius), distance <= Float(outer) else { continue }
                for c in 0..<4 {
                    destRing[c] += dest[col, row, c]
                    sourceRing[c] += source[col, row, c]
                }
                ringCount += 1
            }
        }
        guard ringCount > 0 else { return false }
        let correction = (0..<4).map { (destRing[$0] - sourceRing[$0]) / ringCount }

        let stride = layer.bytesPerRow
        let core = max(0.01, hardness.clamped(to: 0...1))
        for row in 0..<side {
            let y = originY + row
            for col in 0..<side {
                let x = originX + col
                guard x >= 0, y >= 0, x < layer.width, y < layer.height else { continue }
                // Round dab with a soft rim.
                let dx = Float(col - outer), dy = Float(row - outer)
                let distance = (dx * dx + dy * dy).squareRoot() / Float(radius)
                guard distance <= 1 else { continue }
                var weight = distance <= Float(core) ? 1
                    : 1 - (distance - Float(core)) / (1 - Float(core))
                weight = weight.clamped(to: 0...1)
                if let clip, !clip.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5),
                                            using: .evenOdd) { continue }

                let o = (layer.height - 1 - y) * stride + x * 4
                var healed = [Float](repeating: 0, count: 4)
                for c in 0..<4 {
                    healed[c] = (source[col, row, c] + correction[c]).clamped(to: 0...255)
                }
                let alpha = dest[col, row, 3] + (healed[3] - dest[col, row, 3]) * weight
                for c in 0..<3 {
                    let straight = dest[col, row, c] + (healed[c] - dest[col, row, c]) * weight
                    // Back to premultiplied, in the buffer's BGRA order.
                    let premultiplied = (straight * alpha / 255).clamped(to: 0...255)
                    d[o + (2 - c)] = UInt8(premultiplied.rounded())
                }
                d[o + 3] = UInt8(alpha.clamped(to: 0...255).rounded())
            }
        }
        return true
    }

    /// Where a spot heal should take its texture from: whichever nearby patch
    /// of the same size varies least, so the dab borrows clean pixels rather
    /// than whatever blemish sits next door.
    static func bestHealSource(layer: Layer, at center: CGPoint, diameter: CGFloat) -> CGSize? {
        let reach = max(2, diameter * 1.4)
        var best: (offset: CGSize, score: Float)?
        for step in 0..<8 {
            let angle = CGFloat(step) * .pi / 4
            let offset = CGSize(width: (cos(angle) * reach).rounded(),
                                height: (sin(angle) * reach).rounded())
            let radius = max(1, Int((diameter / 2).rounded()))
            let outer = radius + max(2, radius / 3)
            let side = outer * 2 + 1
            let rect = CGRect(x: Int(center.x.rounded()) - outer + Int(offset.width),
                              y: Int(center.y.rounded()) - outer + Int(offset.height),
                              width: side, height: side)
            guard let patch = readPatch(layer, rect: rect) else { continue }
            let score = variance(patch)
            if best == nil || score < best!.score { best = (offset, score) }
        }
        return best?.offset
    }
}

// MARK: - Smudge, blur and sharpen

extension PixelOps {

    /// Box-blurs a patch. Two passes make the falloff smooth enough that a
    /// blur dab does not show its square footprint.
    static func softened(_ patch: Patch, radius: Int) -> Patch {
        guard radius > 0 else { return patch }
        var current = patch
        for _ in 0..<2 {
            current = boxPass(current, radius: radius, horizontal: true)
            current = boxPass(current, radius: radius, horizontal: false)
        }
        return current
    }

    private static func boxPass(_ patch: Patch, radius: Int, horizontal: Bool) -> Patch {
        var out = patch
        let length = horizontal ? patch.width : patch.height
        let lines = horizontal ? patch.height : patch.width
        for line in 0..<lines {
            for i in 0..<length {
                var sums = [Float](repeating: 0, count: 4)
                var count: Float = 0
                for k in (i - radius)...(i + radius) {
                    let j = k.clamped(to: 0...(length - 1))
                    for c in 0..<4 { sums[c] += patch[horizontal ? j : line, horizontal ? line : j, c] }
                    count += 1
                }
                for c in 0..<4 {
                    out[horizontal ? i : line, horizontal ? line : i, c] = sums[c] / count
                }
            }
        }
        return out
    }

    /// The shared shape of every brush that reworks pixels in place: read a
    /// patch, ask `target` what each pixel should become, and fade the answer
    /// in over the round tip.
    @discardableResult
    static func applyDab(layer: Layer,
                         at center: CGPoint,
                         diameter: CGFloat,
                         hardness: CGFloat,
                         amount: CGFloat = 1,
                         margin extra: Int = 0,
                         clip: CGPath? = nil,
                         target: (Patch, Int, Int) -> [Float]) -> Bool {
        let radius = max(1, Int((diameter / 2).rounded()))
        let outer = radius + extra
        let side = outer * 2 + 1
        let originX = Int(center.x.rounded()) - outer
        let originY = Int(center.y.rounded()) - outer
        guard let dest = readPatch(layer, rect: CGRect(x: originX, y: originY, width: side, height: side)),
              let d = layer.data else { return false }

        let stride = layer.bytesPerRow
        let core = max(0.01, hardness.clamped(to: 0...1))
        let strength = Float(amount.clamped(to: 0...1))
        for row in 0..<side {
            let y = originY + row
            for col in 0..<side {
                let x = originX + col
                guard x >= 0, y >= 0, x < layer.width, y < layer.height else { continue }
                let dx = Float(col - outer), dy = Float(row - outer)
                let distance = (dx * dx + dy * dy).squareRoot() / Float(radius)
                guard distance <= 1 else { continue }
                var weight = distance <= Float(core) ? 1
                    : 1 - (distance - Float(core)) / (1 - Float(core))
                weight = weight.clamped(to: 0...1) * strength
                guard weight > 0 else { continue }
                if let clip, !clip.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5),
                                            using: .evenOdd) { continue }

                let wanted = target(dest, col, row)
                let o = (layer.height - 1 - y) * stride + x * 4
                let alpha = dest[col, row, 3] + (wanted[3] - dest[col, row, 3]) * weight
                for c in 0..<3 {
                    let straight = dest[col, row, c] + (wanted[c] - dest[col, row, c]) * weight
                    let premultiplied = (straight * alpha / 255).clamped(to: 0...255)
                    d[o + (2 - c)] = UInt8(premultiplied.rounded())
                }
                d[o + 3] = UInt8(alpha.clamped(to: 0...255).rounded())
            }
        }
        return true
    }

    /// Softens what the tip covers.
    @discardableResult
    static func blurDab(layer: Layer, at center: CGPoint, diameter: CGFloat,
                        strength: CGFloat, hardness: CGFloat, clip: CGPath? = nil) -> Bool {
        let radius = max(1, Int((diameter / 2).rounded()))
        let reach = max(1, radius / 2)
        var blurred: Patch?
        return applyDab(layer: layer, at: center, diameter: diameter, hardness: hardness,
                        amount: strength, margin: reach, clip: clip) { dest, col, row in
            if blurred == nil { blurred = softened(dest, radius: reach) }
            guard let blurred else { return [0, 0, 0, 0] }
            return [blurred[col, row, 0], blurred[col, row, 1],
                    blurred[col, row, 2], blurred[col, row, 3]]
        }
    }

    /// Adds back the detail a blur would remove, which is what sharpening is.
    @discardableResult
    static func sharpenDab(layer: Layer, at center: CGPoint, diameter: CGFloat,
                           strength: CGFloat, hardness: CGFloat, clip: CGPath? = nil) -> Bool {
        let radius = max(1, Int((diameter / 2).rounded()))
        let reach = max(1, radius / 2)
        var blurred: Patch?
        return applyDab(layer: layer, at: center, diameter: diameter, hardness: hardness,
                        amount: strength, margin: reach, clip: clip) { dest, col, row in
            if blurred == nil { blurred = softened(dest, radius: reach) }
            guard let blurred else { return [0, 0, 0, 0] }
            return (0..<4).map { c in
                let detail = dest[col, row, c] - blurred[col, row, c]
                return (dest[col, row, c] + detail * 2).clamped(to: 0...255)
            }
        }
    }

    /// Drags color along the stroke, the way a finger pulls wet paint: each
    /// dab pastes what sat under the previous one.
    @discardableResult
    static func smudgeDab(layer: Layer, from a: CGPoint, to b: CGPoint, diameter: CGFloat,
                          strength: CGFloat, hardness: CGFloat, clip: CGPath? = nil) -> Bool {
        let radius = max(1, Int((diameter / 2).rounded()))
        let side = radius * 2 + 1
        let pickup = CGRect(x: Int(a.x.rounded()) - radius, y: Int(a.y.rounded()) - radius,
                            width: side, height: side)
        guard let carried = readPatch(layer, rect: pickup) else { return false }
        return applyDab(layer: layer, at: b, diameter: diameter, hardness: hardness,
                        amount: strength, clip: clip) { _, col, row in
            [carried[col, row, 0], carried[col, row, 1],
             carried[col, row, 2], carried[col, row, 3]]
        }
    }
}
