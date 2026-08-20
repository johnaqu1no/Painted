import AppKit

extension NSColor {
    /// Colors are mixed and written in sRGB. Named and pattern colors cannot
    /// always convert, in which case the original is close enough to draw with.
    var srgb: NSColor { usingColorSpace(.sRGB) ?? self }
}

extension NSImage {
    /// SF Symbols come and go between macOS releases; a missing one should leave
    /// a blank button rather than trap.
    static func symbol(_ name: String, _ description: String? = nil) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
    }
}
