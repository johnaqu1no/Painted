import AppKit

extension NSColor {
    /// Uppercase hex, with the alpha pair appended only when the color is not
    /// fully opaque: "FF8800" or "FF8800CC".
    var hexString: String {
        let c = srgb
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        let a = Int((c.alphaComponent * 255).rounded())
        let rgb = String(format: "%02X%02X%02X", r, g, b)
        return a == 255 ? rgb : rgb + String(format: "%02X", a)
    }

    /// Accepts RGB, RGBA, RRGGBB and RRGGBBAA, with or without a leading "#".
    static func fromHex(_ text: String) -> NSColor? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }

        // Shorthand repeats each digit: F80 is FF8800.
        if digits.count == 3 || digits.count == 4 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6 || digits.count == 8,
              let value = UInt32(digits, radix: 16) else { return nil }

        let hasAlpha = digits.count == 8
        let r = (value >> (hasAlpha ? 24 : 16)) & 0xFF
        let g = (value >> (hasAlpha ? 16 : 8)) & 0xFF
        let b = (value >> (hasAlpha ? 8 : 0)) & 0xFF
        let a = hasAlpha ? value & 0xFF : 255
        return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                       blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    /// 0–255 components, the units the color fields work in.
    var rgbaBytes: (r: Int, g: Int, b: Int, a: Int) {
        let c = srgb
        return (Int((c.redComponent * 255).rounded()),
                Int((c.greenComponent * 255).rounded()),
                Int((c.blueComponent * 255).rounded()),
                Int((c.alphaComponent * 255).rounded()))
    }

    static func fromBytes(r: Int, g: Int, b: Int, a: Int) -> NSColor {
        func clamp(_ v: Int) -> CGFloat { CGFloat(min(255, max(0, v))) / 255 }
        return NSColor(srgbRed: clamp(r), green: clamp(g), blue: clamp(b), alpha: clamp(a))
    }

    /// Hue in degrees, saturation and value in percent — Paint.NET's units.
    /// The conversion is done on sRGB components so it agrees with the hex and
    /// RGBA fields; AppKit's own hueComponent works in the calibrated space and
    /// reports 360 rather than 0 for red.
    var hsvValues: (h: Int, s: Int, v: Int) {
        let c = srgb
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let high = max(r, g, b), low = min(r, g, b)
        let delta = high - low

        var hue: CGFloat = 0
        if delta > 0 {
            switch high {
            case r: hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            case g: hue = 60 * ((b - r) / delta + 2)
            default: hue = 60 * ((r - g) / delta + 4)
            }
        }
        if hue < 0 { hue += 360 }

        let saturation = high == 0 ? 0 : delta / high
        return (Int(hue.rounded()) % 360,
                Int((saturation * 100).rounded()),
                Int((high * 100).rounded()))
    }

    static func fromHSV(h: Int, s: Int, v: Int, alpha: CGFloat = 1) -> NSColor {
        let hue = CGFloat(((h % 360) + 360) % 360)
        let saturation = CGFloat(min(100, max(0, s))) / 100
        let value = CGFloat(min(100, max(0, v))) / 100

        let chroma = value * saturation
        let x = chroma * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = value - chroma

        let rgb: (CGFloat, CGFloat, CGFloat)
        switch hue {
        case ..<60:   rgb = (chroma, x, 0)
        case ..<120:  rgb = (x, chroma, 0)
        case ..<180:  rgb = (0, chroma, x)
        case ..<240:  rgb = (0, x, chroma)
        case ..<300:  rgb = (x, 0, chroma)
        default:      rgb = (chroma, 0, x)
        }
        return NSColor(srgbRed: rgb.0 + m, green: rgb.1 + m, blue: rgb.2 + m, alpha: alpha)
    }
}
