import CoreGraphics
import Foundation

/// Builds the geometry for every entry in the Shapes tool.
enum ShapeFactory {
    static func path(for kind: ShapeKind, in r: CGRect) -> CGPath {
        let p = CGMutablePath()
        let (x, y, w, h) = (r.minX, r.minY, r.width, r.height)
        switch kind {
        case .rectangle:
            p.addRect(r)
        case .roundedRectangle:
            let radius = min(w, h) * 0.18
            p.addRoundedRect(in: r, cornerWidth: radius, cornerHeight: radius)
        case .ellipse:
            p.addEllipse(in: r)
        case .diamond:
            p.move(to: CGPoint(x: r.midX, y: y))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: x, y: r.midY))
            p.closeSubpath()
        case .triangle:
            p.move(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: y))
            p.addLine(to: CGPoint(x: x, y: y))
            p.closeSubpath()
        case .rightTriangle:
            p.move(to: CGPoint(x: x, y: r.maxY))
            p.addLine(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: r.maxX, y: y))
            p.closeSubpath()
        case .pentagon:
            addRegularPolygon(p, sides: 5, in: r)
        case .hexagon:
            addRegularPolygon(p, sides: 6, in: r)
        case .star:
            addStar(p, points: 6, inner: 0.5, in: r)
        case .fivePointStar:
            addStar(p, points: 5, inner: 0.382, in: r)
        case .heart:
            addHeart(p, in: r)
        case .arrow:
            let shaft = h * 0.3
            p.move(to: CGPoint(x: x, y: r.midY - shaft / 2))
            p.addLine(to: CGPoint(x: x + w * 0.6, y: r.midY - shaft / 2))
            p.addLine(to: CGPoint(x: x + w * 0.6, y: y))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: x + w * 0.6, y: r.maxY))
            p.addLine(to: CGPoint(x: x + w * 0.6, y: r.midY + shaft / 2))
            p.addLine(to: CGPoint(x: x, y: r.midY + shaft / 2))
            p.closeSubpath()
        case .cloud:
            addCloud(p, in: r)
        }
        return p.copy()!
    }

    private static func addRegularPolygon(_ p: CGMutablePath, sides: Int, in r: CGRect) {
        let cx = r.midX, cy = r.midY
        let rx = r.width / 2, ry = r.height / 2
        for i in 0..<sides {
            let a = CGFloat(i) / CGFloat(sides) * 2 * .pi + .pi / 2
            let pt = CGPoint(x: cx + cos(a) * rx, y: cy + sin(a) * ry)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
    }

    private static func addStar(_ p: CGMutablePath, points: Int, inner: CGFloat, in r: CGRect) {
        let cx = r.midX, cy = r.midY
        let rx = r.width / 2, ry = r.height / 2
        let total = points * 2
        for i in 0..<total {
            let scale: CGFloat = (i % 2 == 0) ? 1.0 : inner
            let a = CGFloat(i) / CGFloat(total) * 2 * .pi + .pi / 2
            let pt = CGPoint(x: cx + cos(a) * rx * scale, y: cy + sin(a) * ry * scale)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
    }

    private static func addHeart(_ p: CGMutablePath, in r: CGRect) {
        let w = r.width, h = r.height
        let x = r.minX, y = r.minY
        // Drawn in a unit square then mapped onto r; y grows upward.
        p.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.05))
        p.addCurve(to: CGPoint(x: x, y: y + h * 0.70),
                   control1: CGPoint(x: x + w * 0.12, y: y + h * 0.30),
                   control2: CGPoint(x: x, y: y + h * 0.48))
        p.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.85),
                   control1: CGPoint(x: x, y: y + h * 1.00),
                   control2: CGPoint(x: x + w * 0.32, y: y + h * 1.00))
        p.addCurve(to: CGPoint(x: x + w, y: y + h * 0.70),
                   control1: CGPoint(x: x + w * 0.68, y: y + h * 1.00),
                   control2: CGPoint(x: x + w, y: y + h * 1.00))
        p.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.05),
                   control1: CGPoint(x: x + w, y: y + h * 0.48),
                   control2: CGPoint(x: x + w * 0.88, y: y + h * 0.30))
        p.closeSubpath()
    }

    private static func addCloud(_ p: CGMutablePath, in r: CGRect) {
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        p.addEllipse(in: CGRect(x: x, y: y, width: w * 0.55, height: h * 0.6))
        p.addEllipse(in: CGRect(x: x + w * 0.20, y: y + h * 0.25, width: w * 0.5, height: h * 0.75))
        p.addEllipse(in: CGRect(x: x + w * 0.45, y: y, width: w * 0.55, height: h * 0.62))
        p.addEllipse(in: CGRect(x: x + w * 0.30, y: y, width: w * 0.45, height: h * 0.5))
    }
}
