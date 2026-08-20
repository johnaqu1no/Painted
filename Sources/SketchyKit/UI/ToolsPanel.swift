import AppKit

/// Floating home for the tool grid. All the layout lives in ToolsPaletteView so
/// the same view works docked in a rail.
final class ToolsPanel: FloatingPanel {
    let palette = ToolsPaletteView(frame: .zero)
    var onSelect: ((ToolID) -> Void)?

    init() {
        let width = ToolsPaletteView(frame: .zero).width(forColumns: 2)
        let height = ToolsPaletteView(frame: .zero).preferredHeight(forWidth: width) ?? 340
        super.init(title: "Tools", size: NSSize(width: width, height: height))
        styleMask.insert(.resizable)
        contentMinSize = NSSize(width: 50, height: 80)
        palette.frame = NSRect(x: 0, y: 0, width: width, height: height)
        palette.autoresizingMask = [.width, .height]
        palette.onSelect = { [weak self] tool in self?.onSelect?(tool) }
        contentView = palette
    }

    func select(_ tool: ToolID) { palette.select(tool) }
}
