import CoreGraphics
import Foundation

/// Layer blend modes, mirroring the set Paint.NET exposes.
enum LayerBlendMode: String, CaseIterable, Codable {
    case normal = "Normal"
    case multiply = "Multiply"
    case additive = "Additive"
    case colorBurn = "Color Burn"
    case colorDodge = "Color Dodge"
    case reflect = "Reflect"
    case glow = "Glow"
    case overlay = "Overlay"
    case difference = "Difference"
    case negation = "Negation"
    case lighten = "Lighten"
    case darken = "Darken"
    case screen = "Screen"
    case xor = "Xor"

    var cgBlendMode: CGBlendMode {
        switch self {
        case .normal:     return .normal
        case .multiply:   return .multiply
        case .additive:   return .plusLighter
        case .colorBurn:  return .colorBurn
        case .colorDodge: return .colorDodge
        case .reflect:    return .colorDodge
        case .glow:       return .softLight
        case .overlay:    return .overlay
        case .difference: return .difference
        case .negation:   return .exclusion
        case .lighten:    return .lighten
        case .darken:     return .darken
        case .screen:     return .screen
        case .xor:        return .xor
        }
    }
}
