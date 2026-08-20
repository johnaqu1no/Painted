import AppKit
import CoreGraphics
import UniformTypeIdentifiers

/// The image being edited: a stack of layers, a selection, and an undo history.
final class Document {
    private(set) var width: Int
    private(set) var height: Int
    var layers: [Layer] = []
    var selectedLayerIndex: Int = 0
    /// Active selection in image coordinates; nil means "everything".
    var selectionPath: CGPath?
    var fileURL: URL?
    var isDirty: Bool = false

    let history = HistoryManager()

    var onChange: (() -> Void)?
    var onStructureChange: (() -> Void)?

    var size: CGSize { CGSize(width: width, height: height) }
    var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }

    var selectedLayer: Layer? {
        guard layers.indices.contains(selectedLayerIndex) else { return nil }
        return layers[selectedLayerIndex]
    }

    var displayName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    init(width: Int, height: Int, background: NSColor? = .white) {
        self.width = max(1, width)
        self.height = max(1, height)
        let base = Layer(width: self.width, height: self.height, name: "Background")
        if let background { base.fill(with: background) }
        layers = [base]
        history.reset(with: snapshot(title: "Background"))
    }

    convenience init(image: CGImage, url: URL?) {
        self.init(width: image.width, height: image.height, background: nil)
        layers[0].draw(image: image)
        fileURL = url
        history.reset(with: snapshot(title: "Open"))
    }

    // MARK: - Snapshots / undo

    func snapshot(title: String) -> HistorySnapshot {
        HistorySnapshot(
            title: title,
            layers: layers.map {
                .init(name: $0.name, visible: $0.isVisible, opacity: $0.opacity,
                      blend: $0.blendMode, image: $0.image)
            },
            selectedIndex: selectedLayerIndex,
            width: width, height: height)
    }

    func commit(_ title: String) {
        history.push(snapshot(title: title))
        isDirty = true
        onChange?()
    }

    func apply(_ snap: HistorySnapshot) {
        width = snap.width
        height = snap.height
        layers = snap.layers.map { st in
            let l = Layer(width: snap.width, height: snap.height, name: st.name)
            l.isVisible = st.visible
            l.opacity = st.opacity
            l.blendMode = st.blend
            if let img = st.image { l.draw(image: img) }
            return l
        }
        selectedLayerIndex = min(snap.selectedIndex, layers.count - 1)
        isDirty = true
        onStructureChange?()
        onChange?()
    }

    @discardableResult func undo() -> Bool {
        guard let s = history.undo() else { return false }
        apply(s); return true
    }

    @discardableResult func redo() -> Bool {
        guard let s = history.redo() else { return false }
        apply(s); return true
    }

    func jumpHistory(to index: Int) {
        if let s = history.jump(to: index) { apply(s) }
    }

    // MARK: - Layer operations

    func addLayer(named name: String? = nil) {
        let l = Layer(width: width, height: height, name: name ?? "Layer \(layers.count + 1)")
        layers.insert(l, at: selectedLayerIndex + 1)
        selectedLayerIndex += 1
        commit("Add Layer")
        onStructureChange?()
    }

    func deleteSelectedLayer() {
        guard layers.count > 1, layers.indices.contains(selectedLayerIndex) else { return }
        layers.remove(at: selectedLayerIndex)
        selectedLayerIndex = min(selectedLayerIndex, layers.count - 1)
        commit("Delete Layer")
        onStructureChange?()
    }

    func duplicateSelectedLayer() {
        guard let l = selectedLayer else { return }
        layers.insert(l.copyLayer(), at: selectedLayerIndex + 1)
        selectedLayerIndex += 1
        commit("Duplicate Layer")
        onStructureChange?()
    }

    func mergeLayerDown() {
        guard selectedLayerIndex > 0 else { return }
        let upper = layers[selectedLayerIndex]
        let lower = layers[selectedLayerIndex - 1]
        if let img = upper.image, upper.isVisible {
            lower.context.saveGState()
            lower.context.setAlpha(upper.opacity)
            lower.context.setBlendMode(upper.blendMode.cgBlendMode)
            lower.context.draw(img, in: bounds)
            lower.context.restoreGState()
        }
        layers.remove(at: selectedLayerIndex)
        selectedLayerIndex -= 1
        commit("Merge Layer Down")
        onStructureChange?()
    }

    func flatten() {
        guard layers.count > 1 else { return }
        let flat = Layer(width: width, height: height, name: "Background")
        if let img = composite() { flat.draw(image: img) }
        layers = [flat]
        selectedLayerIndex = 0
        commit("Flatten")
        onStructureChange?()
    }

    func moveLayer(from: Int, to: Int) {
        guard layers.indices.contains(from), to >= 0, to < layers.count, from != to else { return }
        let l = layers.remove(at: from)
        layers.insert(l, at: to)
        selectedLayerIndex = to
        commit("Reorder Layer")
        onStructureChange?()
    }

    // MARK: - Compositing

    func composite() -> CGImage? {
        let ctx = Layer.makeContext(width: width, height: height)
        for layer in layers where layer.isVisible && layer.opacity > 0 {
            guard let img = layer.image else { continue }
            ctx.saveGState()
            ctx.setAlpha(layer.opacity)
            ctx.setBlendMode(layer.blendMode.cgBlendMode)
            ctx.draw(img, in: bounds)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    // MARK: - Canvas geometry

    func resizeCanvas(to newSize: CGSize, anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        let nw = max(1, Int(newSize.width.rounded()))
        let nh = max(1, Int(newSize.height.rounded()))
        let dx = (CGFloat(nw) - CGFloat(width)) * anchor.x
        let dy = (CGFloat(nh) - CGFloat(height)) * anchor.y
        layers = layers.map { old in
            let l = Layer(width: nw, height: nh, name: old.name)
            l.isVisible = old.isVisible; l.opacity = old.opacity; l.blendMode = old.blendMode
            if let img = old.image {
                l.context.draw(img, in: CGRect(x: dx, y: dy, width: CGFloat(old.width), height: CGFloat(old.height)))
            }
            return l
        }
        width = nw; height = nh
        selectionPath = nil
        commit("Canvas Size")
        onStructureChange?()
    }

    /// Resamples every layer. `fit` keeps the original proportions and places
    /// the scaled image with `anchor`, padding the rest with transparency;
    /// otherwise the image is stretched to the new size and the anchor is moot.
    func resizeImage(to newSize: CGSize,
                     anchor: CGPoint = CGPoint(x: 0.5, y: 0.5),
                     fit: Bool = false,
                     resampling: Resampling = .pixels) {
        let nw = max(1, Int(newSize.width.rounded()))
        let nh = max(1, Int(newSize.height.rounded()))

        var target = CGRect(x: 0, y: 0, width: nw, height: nh)
        if fit {
            let scale = min(CGFloat(nw) / CGFloat(width), CGFloat(nh) / CGFloat(height))
            let size = CGSize(width: (CGFloat(width) * scale).rounded(),
                              height: (CGFloat(height) * scale).rounded())
            target = CGRect(x: ((CGFloat(nw) - size.width) * anchor.x).rounded(),
                            y: ((CGFloat(nh) - size.height) * anchor.y).rounded(),
                            width: size.width, height: size.height)
        }

        layers = layers.map { old in
            let l = Layer(width: nw, height: nh, name: old.name)
            l.isVisible = old.isVisible; l.opacity = old.opacity; l.blendMode = old.blendMode
            if let img = old.image {
                l.context.interpolationQuality = resampling.quality
                l.context.draw(img, in: target)
            }
            return l
        }
        width = nw; height = nh
        selectionPath = nil
        commit("Image Size")
        onStructureChange?()
    }

    /// Rotate the whole image by a multiple of 90 degrees (counter-clockwise turns).
    func rotate(turns: Int) {
        let t = ((turns % 4) + 4) % 4
        guard t != 0 else { return }
        let swap = (t % 2 == 1)
        let nw = swap ? height : width
        let nh = swap ? width : height
        layers = layers.map { old in
            let l = Layer(width: nw, height: nh, name: old.name)
            l.isVisible = old.isVisible; l.opacity = old.opacity; l.blendMode = old.blendMode
            if let img = old.image {
                l.context.translateBy(x: CGFloat(nw) / 2, y: CGFloat(nh) / 2)
                l.context.rotate(by: CGFloat(t) * .pi / 2)
                l.context.draw(img, in: CGRect(x: -CGFloat(old.width) / 2, y: -CGFloat(old.height) / 2,
                                               width: CGFloat(old.width), height: CGFloat(old.height)))
            }
            return l
        }
        width = nw; height = nh
        selectionPath = nil
        commit("Rotate")
        onStructureChange?()
    }

    /// Free rotate / scale / pan of a single layer, resampled in place.
    func transformLayer(_ layer: Layer, angle: CGFloat, scale: CGFloat, offset: CGPoint) {
        guard let img = layer.image else { return }
        layer.clear()
        let ctx = layer.context
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(layer.width) / 2 + offset.x, y: CGFloat(layer.height) / 2 + offset.y)
        ctx.rotate(by: angle)
        ctx.scaleBy(x: scale, y: scale)
        ctx.draw(img, in: CGRect(x: -CGFloat(layer.width) / 2, y: -CGFloat(layer.height) / 2,
                                 width: CGFloat(layer.width), height: CGFloat(layer.height)))
        ctx.restoreGState()
    }

    func flip(horizontal: Bool, layerOnly: Bool = false) {
        let targets = layerOnly ? [selectedLayer].compactMap { $0 } : layers
        for old in targets {
            guard let img = old.image else { continue }
            old.clear()
            old.context.saveGState()
            if horizontal {
                old.context.translateBy(x: CGFloat(old.width), y: 0)
                old.context.scaleBy(x: -1, y: 1)
            } else {
                old.context.translateBy(x: 0, y: CGFloat(old.height))
                old.context.scaleBy(x: 1, y: -1)
            }
            old.context.draw(img, in: CGRect(x: 0, y: 0, width: old.width, height: old.height))
            old.context.restoreGState()
        }
        commit(horizontal ? "Flip Horizontal" : "Flip Vertical")
    }

    // MARK: - Selection helpers

    /// Clears the selected region on the active layer — or the whole layer when
    /// nothing is selected. Returns false when there was nothing to erase.
    @discardableResult
    func eraseSelection() -> Bool {
        guard let layer = selectedLayer else { return false }
        let region = selectionPath ?? CGPath(rect: bounds, transform: nil)
        layer.context.saveGState()
        layer.context.addPath(region)
        layer.context.clip(using: .evenOdd)
        layer.context.clear(bounds)
        layer.context.restoreGState()
        commit(selectionPath == nil ? "Erase Layer" : "Erase Selection")
        return true
    }

    /// Draws an image into the active layer and selects what was pasted, so it
    /// can be dragged straight away. Without an origin it lands in the top-left
    /// corner, or at the top-left of the current selection when there is one.
    @discardableResult
    func paste(_ image: CGImage, at origin: CGPoint? = nil) -> CGRect? {
        guard let layer = selectedLayer else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        let corner = origin
            ?? selectionPath?.boundingBoxOfPath.origin.applying(
                CGAffineTransform(translationX: 0, y: (selectionPath?.boundingBoxOfPath.height ?? 0) - size.height))
            ?? CGPoint(x: 0, y: CGFloat(height) - size.height)

        let destination = CGRect(origin: corner, size: size)
        layer.context.draw(image, in: destination)
        selectionPath = CGPath(rect: destination, transform: nil)
        commit("Paste")
        return destination
    }

    /// What to do when pasted pixels do not fit the canvas.
    enum PasteFit {
        /// Grow the canvas so the whole image fits, keeping the current art.
        case expandCanvas
        /// Make the canvas exactly the size of the pasted image.
        case cropToImage
        /// Leave the canvas alone; the paste hangs over the edge until dropped.
        case keepCanvas

        /// Canvas size this choice implies for an image of `imageSize`.
        func canvasSize(current: CGSize, imageSize: CGSize) -> CGSize {
            switch self {
            case .expandCanvas:
                return CGSize(width: max(current.width, imageSize.width),
                              height: max(current.height, imageSize.height))
            case .cropToImage:
                return imageSize
            case .keepCanvas:
                return current
            }
        }
    }

    /// True when an image would hang over the edge of the canvas.
    func exceedsCanvas(_ imageSize: CGSize) -> Bool {
        imageSize.width > CGFloat(width) || imageSize.height > CGFloat(height)
    }

    func selectAll() {
        selectionPath = CGPath(rect: bounds, transform: nil)
        onChange?()
    }

    func deselect() {
        selectionPath = nil
        onChange?()
    }

    func invertSelection() {
        guard let sel = selectionPath else { selectionPath = nil; return }
        let p = CGMutablePath()
        p.addRect(bounds)
        p.addPath(sel)
        selectionPath = p.copy(using: nil)
        onChange?()
    }

    /// Applies the current selection as a clip on a context (image coordinates).
    func clipToSelection(_ ctx: CGContext) {
        guard let sel = selectionPath else { return }
        ctx.addPath(sel)
        ctx.clip(using: .evenOdd)
    }

    // MARK: - IO

    // MARK: - Native .sketchy documents

    static let nativeExtension = "sketchy"
    /// Documents saved before the rename still open.
    static let legacyExtension = "ptd"

    static func isNative(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == nativeExtension || ext == legacyExtension
    }

    /// Sketchy's own layered format: a binary property list holding the layer
    /// stack, each layer's pixels stored as PNG. Files written before the app
    /// was renamed carry the .ptd extension and an older format marker; both
    /// still open.
    func writeNative(to url: URL) throws {
        var layerDicts: [[String: Any]] = []
        for layer in layers {
            guard let img = layer.image,
                  let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else {
                throw DocumentError.encodeFailed
            }
            layerDicts.append([
                "name": layer.name,
                "visible": layer.isVisible,
                "opacity": Double(layer.opacity),
                "blend": layer.blendMode.rawValue,
                "png": png
            ])
        }
        let root: [String: Any] = [
            "format": "Sketchy Document",
            "version": 1,
            "width": width,
            "height": height,
            "selectedLayer": selectedLayerIndex,
            "layers": layerDicts
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try data.write(to: url)
        fileURL = url
        isDirty = false
    }

    static func openNative(url: URL) throws -> Document {
        let data = try Data(contentsOf: url)
        guard let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any],
              ["Sketchy Document", "Painted Document"].contains(root["format"] as? String ?? ""),
              let width = root["width"] as? Int,
              let height = root["height"] as? Int,
              let layerDicts = root["layers"] as? [[String: Any]], !layerDicts.isEmpty else {
            throw DocumentError.decodeFailed
        }
        let doc = Document(width: width, height: height, background: nil)
        doc.layers = layerDicts.enumerated().map { index, dict in
            let layer = Layer(width: width, height: height, name: dict["name"] as? String ?? "Layer \(index + 1)")
            layer.isVisible = dict["visible"] as? Bool ?? true
            layer.opacity = CGFloat(dict["opacity"] as? Double ?? 1)
            layer.blendMode = LayerBlendMode(rawValue: dict["blend"] as? String ?? "") ?? .normal
            if let png = dict["png"] as? Data,
               let src = CGImageSourceCreateWithData(png as CFData, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                layer.draw(image: img)
            }
            return layer
        }
        doc.selectedLayerIndex = min(root["selectedLayer"] as? Int ?? 0, doc.layers.count - 1)
        doc.fileURL = url
        doc.isDirty = false
        doc.history.reset(with: doc.snapshot(title: "Open"))
        return doc
    }

    /// True when the document keeps its layers on disk instead of flattening.
    var isNativeFile: Bool {
        fileURL.map(Document.isNative) ?? false
    }

    func write(to url: URL) throws {
        if Document.isNative(url) {
            try writeNative(to: url)
            return
        }
        guard let img = composite() else { throw DocumentError.encodeFailed }
        let rep = NSBitmapImageRep(cgImage: img)
        rep.size = NSSize(width: width, height: height)
        let ext = url.pathExtension.lowercased()
        let type: NSBitmapImageRep.FileType
        var props: [NSBitmapImageRep.PropertyKey: Any] = [:]
        switch ext {
        case "jpg", "jpeg":
            type = .jpeg
            props[.compressionFactor] = 0.92
        case "tiff", "tif": type = .tiff
        case "bmp":         type = .bmp
        case "gif":         type = .gif
        default:            type = .png
        }
        guard let data = rep.representation(using: type, properties: props) else {
            throw DocumentError.encodeFailed
        }
        try data.write(to: url)
        fileURL = url
        isDirty = false
    }

    static func open(url: URL) throws -> Document {
        if Document.isNative(url) {
            return try openNative(url: url)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw DocumentError.decodeFailed
        }
        return Document(image: img, url: url)
    }
}

enum DocumentError: Error, LocalizedError {
    case encodeFailed, decodeFailed
    var errorDescription: String? {
        switch self {
        case .encodeFailed: return "Sketchy could not encode that image format."
        case .decodeFailed: return "Sketchy could not read that file."
        }
    }
}
