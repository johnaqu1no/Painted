// Renders Sketchy's app icon — a brush swirl sweeping from the top right down
// to the bottom left — and packs it into an .icns.
// Run with: swift tools/MakeIcon.swift
import AppKit
import Foundation

/// One point along the stroke: where it is and how wide the brush is there.
private struct Sample {
    let point: CGPoint
    let width: CGFloat
}

/// Cubic bezier through four control points.
private func bezier(_ t: CGFloat, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGPoint {
    let u = 1 - t
    let x = u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x
    let y = u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y
    return CGPoint(x: x, y: y)
}

/// Builds a filled outline around the samples, offsetting each one along its
/// normal. A plain stroke cannot taper, and the taper is what reads as a brush.
private func ribbon(_ samples: [Sample]) -> CGPath {
    let path = CGMutablePath()
    guard samples.count > 1 else { return path }

    func normal(at index: Int) -> CGPoint {
        let previous = samples[max(0, index - 1)].point
        let following = samples[min(samples.count - 1, index + 1)].point
        let dx = following.x - previous.x
        let dy = following.y - previous.y
        let length = max(0.0001, hypot(dx, dy))
        return CGPoint(x: -dy / length, y: dx / length)
    }

    var forward: [CGPoint] = []
    var back: [CGPoint] = []
    for (index, sample) in samples.enumerated() {
        let n = normal(at: index)
        let half = sample.width / 2
        forward.append(CGPoint(x: sample.point.x + n.x * half, y: sample.point.y + n.y * half))
        back.append(CGPoint(x: sample.point.x - n.x * half, y: sample.point.y - n.y * half))
    }

    path.move(to: forward[0])
    for p in forward.dropFirst() { path.addLine(to: p) }
    for p in back.reversed() { path.addLine(to: p) }
    path.closeSubpath()
    return path
}

/// The brush that painted the swirl, sitting at its tail: bristle tip on the
/// end of the stroke, handle carrying on in the direction of travel. Returned
/// as paths so the whole composition can be measured and centred.
private func brushPaths(tip: CGPoint, angle: CGFloat, scale s: CGFloat) -> [(CGPath, NSColor)] {
    var transform = CGAffineTransform(translationX: tip.x, y: tip.y).rotated(by: angle)

    // Local space: +x runs from the tip back along the handle.
    let bristleLength = 116 * s
    let ferruleLength = 62 * s
    let handleLength = 196 * s
    let halfBristle = 29 * s
    let halfFerrule = 35 * s
    let halfHandle = 30 * s
    let halfEnd = 18 * s

    let bristles = CGMutablePath()
    bristles.move(to: .zero)
    bristles.addQuadCurve(to: CGPoint(x: bristleLength, y: -halfBristle),
                          control: CGPoint(x: bristleLength * 0.45, y: -halfBristle * 0.75))
    bristles.addLine(to: CGPoint(x: bristleLength, y: halfBristle))
    bristles.addQuadCurve(to: .zero,
                          control: CGPoint(x: bristleLength * 0.45, y: halfBristle * 0.75))
    bristles.closeSubpath()

    let ferrule = CGPath(roundedRect: CGRect(x: bristleLength, y: -halfFerrule,
                                             width: ferruleLength, height: halfFerrule * 2),
                         cornerWidth: 12 * s, cornerHeight: 12 * s, transform: nil)

    let handleStart = bristleLength + ferruleLength - 4 * s
    let handleEnd = handleStart + handleLength
    let handle = CGMutablePath()
    handle.move(to: CGPoint(x: handleStart, y: -halfHandle))
    handle.addLine(to: CGPoint(x: handleEnd - halfEnd, y: -halfEnd))
    handle.addArc(center: CGPoint(x: handleEnd - halfEnd, y: 0), radius: halfEnd,
                  startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    handle.addLine(to: CGPoint(x: handleStart, y: halfHandle))
    handle.closeSubpath()

    return [
        (bristles.copy(using: &transform) ?? bristles, NSColor(srgbRed: 0.98, green: 0.36, blue: 0.40, alpha: 1)),
        (ferrule.copy(using: &transform) ?? ferrule, NSColor(srgbRed: 0.74, green: 0.78, blue: 0.84, alpha: 1)),
        (handle.copy(using: &transform) ?? handle, NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1))
    ]
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }
    let s = size / 1024   // the artwork is authored at 1024pt

    // Rounded-square backdrop.
    let inset: CGFloat = 40 * s
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 200 * s, cornerHeight: 200 * s, transform: nil))
    ctx.clip()
    let backdrop = [NSColor(srgbRed: 0.16, green: 0.20, blue: 0.30, alpha: 1).cgColor,
                    NSColor(srgbRed: 0.07, green: 0.09, blue: 0.15, alpha: 1).cgColor]
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: backdrop as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
    }

    // The swirl: a loop near the top right unwinding into a long sweep that
    // tails off at the bottom left.
    let curves: [(CGPoint, CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: 820, y: 790), CGPoint(x: 700, y: 900), CGPoint(x: 470, y: 870), CGPoint(x: 470, y: 720)),
        (CGPoint(x: 470, y: 720), CGPoint(x: 470, y: 600), CGPoint(x: 700, y: 600), CGPoint(x: 700, y: 470)),
        (CGPoint(x: 700, y: 470), CGPoint(x: 705, y: 345), CGPoint(x: 540, y: 372), CGPoint(x: 440, y: 330))
    ]

    var samples: [Sample] = []
    let stepsPerCurve = 60
    let total = CGFloat(curves.count * stepsPerCurve)
    for (index, curve) in curves.enumerated() {
        for step in 0...stepsPerCurve {
            let t = CGFloat(step) / CGFloat(stepsPerCurve)
            let progress = (CGFloat(index * stepsPerCurve) + CGFloat(step)) / total
            // Thin where the brush lands, fattest just past the middle, drawn
            // out to a fine point as it lifts off at the bottom left.
            let swell = pow(sin(progress * .pi), 0.55)
            let liftOff = 1 - pow(progress, 2.2) * 0.75
            let width = (14 + 74 * swell * liftOff) * s
            samples.append(Sample(point: bezier(t, curve.0, curve.1, curve.2, curve.3)
                                    .applying(CGAffineTransform(scaleX: s, y: s)),
                                  width: width))
        }
    }

    let swirl = ribbon(samples)
    var brush: [(CGPath, NSColor)] = []
    if let last = samples.last, samples.count > 2 {
        let previous = samples[samples.count - 3].point
        let angle = atan2(last.point.y - previous.y, last.point.x - previous.x)
        brush = brushPaths(tip: last.point, angle: angle, scale: s)
    }

    // Centre the whole composition in the tile so the padding matches on every
    // side, rather than depending on where the curve happens to land.
    let artwork = brush.reduce(swirl.boundingBoxOfPath) { $0.union($1.0.boundingBoxOfPath) }
    let padding = 118 * s
    let frame = rect.insetBy(dx: padding, dy: padding)
    let fit = min(frame.width / artwork.width, frame.height / artwork.height)
    var centre = CGAffineTransform(translationX: frame.midX, y: frame.midY)
        .scaledBy(x: fit, y: fit)
        .translatedBy(x: -artwork.midX, y: -artwork.midY)

    ctx.addPath(swirl.copy(using: &centre) ?? swirl)
    ctx.clip()
    let ink = [NSColor(srgbRed: 1.0, green: 0.54, blue: 0.31, alpha: 1).cgColor,
               NSColor(srgbRed: 0.98, green: 0.31, blue: 0.42, alpha: 1).cgColor]
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: ink as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: size, y: size), end: CGPoint(x: 0, y: 0),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    ctx.restoreGState()

    for (path, colour) in brush {
        ctx.addPath(path.copy(using: &centre) ?? path)
        ctx.setFillColor(colour.cgColor)
        ctx.fillPath()
    }

    if ProcessInfo.processInfo.environment["ICON_MARGINS"] != nil, size > 500 {
        let placed = artwork.applying(centre)
        print(String(format: "margins — left %.0f right %.0f bottom %.0f top %.0f",
                     placed.minX - rect.minX, rect.maxX - placed.maxX,
                     placed.minY - rect.minY, rect.maxY - placed.maxY))
    }

    image.unlockFocus()
    return image
}

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x")
]
for (px, name) in variants {
    let img = drawIcon(size: CGFloat(px))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: iconset.appendingPathComponent("\(name).png"))
}

let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = ["-c", "icns", iconset.path, "-o", "Sources/Sketchy/Resources/AppIcon.icns"]
try convert.run()
convert.waitUntilExit()
print(convert.terminationStatus == 0 ? "Wrote Sources/Sketchy/Resources/AppIcon.icns" : "iconutil failed")
