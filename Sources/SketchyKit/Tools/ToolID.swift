import AppKit

enum ToolID: String, CaseIterable {
    case rectangleSelect, moveSelectedPixels
    case lassoSelect, moveSelection
    case ellipseSelect, zoom
    case magicWand, pan
    case paintBucket, gradient
    case paintbrush, eraser
    case pencil, colorPicker
    case cloneStamp, recolor
    case text, line
    case shapes

    var title: String {
        switch self {
        case .rectangleSelect:    return "Rectangle Select"
        case .moveSelectedPixels: return "Move Selected Pixels"
        case .lassoSelect:        return "Lasso Select"
        case .moveSelection:      return "Move Selection"
        case .ellipseSelect:      return "Ellipse Select"
        case .zoom:               return "Zoom"
        case .magicWand:          return "Magic Wand"
        case .pan:                return "Pan"
        case .paintBucket:        return "Paint Bucket"
        case .gradient:           return "Gradient"
        case .paintbrush:         return "Paintbrush"
        case .eraser:             return "Eraser"
        case .pencil:             return "Pencil"
        case .colorPicker:        return "Color Picker"
        case .cloneStamp:         return "Clone Stamp"
        case .recolor:            return "Recolor"
        case .text:               return "Text"
        case .line:               return "Line / Curve"
        case .shapes:             return "Shapes"
        }
    }

    /// SF Symbol used in the Tools palette.
    var symbol: String {
        switch self {
        case .rectangleSelect:    return "rectangle.dashed"
        case .moveSelectedPixels: return "arrow.up.and.down.and.arrow.left.and.right"
        case .lassoSelect:        return "lasso"
        case .moveSelection:      return "rectangle.dashed.and.paperclip"
        case .ellipseSelect:      return "circle.dashed"
        case .zoom:               return "magnifyingglass"
        case .magicWand:          return "wand.and.stars"
        case .pan:                return "hand.raised"
        case .paintBucket:        return "drop.fill"
        case .gradient:           return "square.righthalf.filled"
        case .paintbrush:         return "paintbrush.pointed"
        case .eraser:             return "eraser"
        case .pencil:             return "pencil"
        case .colorPicker:        return "eyedropper"
        case .cloneStamp:         return "doc.on.doc"
        case .recolor:            return "circle.lefthalf.filled"
        case .text:               return "textformat"
        case .line:               return "line.diagonal"
        case .shapes:             return "square.on.circle"
        }
    }

    var keyEquivalent: String {
        switch self {
        case .rectangleSelect:    return "s"
        case .moveSelectedPixels: return "m"
        case .lassoSelect:        return "s"
        case .moveSelection:      return "m"
        case .ellipseSelect:      return "s"
        case .zoom:               return "z"
        case .magicWand:          return "w"
        case .pan:                return "h"
        case .paintBucket:        return "f"
        case .gradient:           return "g"
        case .paintbrush:         return "b"
        case .eraser:             return "e"
        case .pencil:             return "p"
        case .colorPicker:        return "k"
        case .cloneStamp:         return "l"
        case .recolor:            return "r"
        case .text:               return "t"
        case .line:               return "o"
        case .shapes:             return "o"
        }
    }

    var isSelectionTool: Bool {
        switch self {
        case .rectangleSelect, .ellipseSelect, .lassoSelect, .magicWand: return true
        default: return false
        }
    }

    /// Order of the two-column palette, matching the reference layout.
    static let paletteOrder: [ToolID] = [
        .rectangleSelect, .moveSelectedPixels,
        .lassoSelect, .moveSelection,
        .ellipseSelect, .zoom,
        .magicWand, .pan,
        .paintBucket, .gradient,
        .paintbrush, .eraser,
        .pencil, .colorPicker,
        .cloneStamp, .recolor,
        .text, .line,
        .shapes
    ]
}

enum ShapeKind: String, CaseIterable {
    case rectangle = "Rectangle"
    case roundedRectangle = "Rounded Rectangle"
    case ellipse = "Ellipse"
    case diamond = "Diamond"
    case triangle = "Triangle"
    case rightTriangle = "Right Triangle"
    case pentagon = "Pentagon"
    case hexagon = "Hexagon"
    case star = "Star"
    case fivePointStar = "5-Point Star"
    case heart = "Heart"
    case arrow = "Arrow"
    case cloud = "Cloud"

    var symbol: String {
        switch self {
        case .rectangle:        return "rectangle"
        case .roundedRectangle: return "rectangle.roundedtop"
        case .ellipse:          return "circle"
        case .diamond:          return "diamond"
        case .triangle:         return "triangle"
        case .rightTriangle:    return "triangle.righthalf.filled"
        case .pentagon:         return "pentagon"
        case .hexagon:          return "hexagon"
        case .star:             return "star"
        case .fivePointStar:    return "star.fill"
        case .heart:            return "heart"
        case .arrow:            return "arrowshape.right"
        case .cloud:            return "cloud"
        }
    }
}

enum DrawMode: Int, CaseIterable {
    case outline, fill, outlineAndFill
    var symbol: String {
        switch self {
        case .outline:        return "rectangle"
        case .fill:           return "rectangle.fill"
        case .outlineAndFill: return "rectangle.inset.filled"
        }
    }
    var title: String {
        switch self {
        case .outline:        return "Draw Shape Outline"
        case .fill:           return "Draw Filled Shape"
        case .outlineAndFill: return "Draw Filled Shape With Outline"
        }
    }
}

enum StrokeStyle: String, CaseIterable {
    case solid = "Solid"
    case dashed = "Dashed"
    case dotted = "Dotted"
    case dashDot = "Dash Dot"

    var pattern: [CGFloat]? {
        switch self {
        case .solid:   return nil
        case .dashed:  return [6, 4]
        case .dotted:  return [1, 3]
        case .dashDot: return [6, 3, 1, 3]
        }
    }
}

enum FillStyle: String, CaseIterable {
    case solidColor = "Solid Color"
    case none = "None"
    case horizontalLines = "Horizontal Lines"
    case verticalLines = "Vertical Lines"
    case diagonalLines = "Diagonal Lines"
    case checker = "Checkerboard"
}

enum GradientKind: String, CaseIterable {
    case linear = "Linear"
    case reflected = "Reflected"
    case radial = "Radial"
    case conical = "Conical"
}

/// How pixels are resampled when something is scaled.
enum Resampling: String, CaseIterable {
    /// Nearest neighbour: every source pixel stays a hard-edged block.
    case pixels = "Pixels"
    /// Smooth interpolation, better for photographs.
    case smooth = "Smooth"

    var quality: CGInterpolationQuality {
        self == .pixels ? .none : .high
    }
}

enum SelectionMode: String, CaseIterable {
    case replace = "Replace"
    case union = "Add (union)"
    case exclude = "Subtract"
    case intersect = "Intersect"
    case xor = "Xor"
}

/// Everything the options bar can tweak, shared by every tool.
final class ToolSettings {
    var tool: ToolID = .paintbrush
    var brushWidth: CGFloat = 4
    var hardness: CGFloat = 0.75
    var tolerance: CGFloat = 0.30
    var shape: ShapeKind = .rectangle
    var drawMode: DrawMode = .outlineAndFill
    var strokeStyle: StrokeStyle = .solid
    var fillStyle: FillStyle = .solidColor
    var gradientKind: GradientKind = .linear
    var selectionMode: SelectionMode = .replace
    var blendMode: LayerBlendMode = .normal
    var antialiasing: Bool = true
    var fontName: String = "Helvetica"
    var fontSize: CGFloat = 24
    var bold = false, italic = false, underline = false
    var sampleMerged: Bool = false
    /// Pixel art is the common case for a canvas this size, so scaling keeps
    /// hard edges unless the user asks for smoothing.
    var resampling: Resampling = .pixels
    var fillGlobally: Bool = false
}
