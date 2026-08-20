import Foundation

/// The keyboard shortcut assigned to each tool, and where changes are kept.
/// Several tools may share a key: pressing it cycles through them, which is how
/// the three selection tools live on one letter.
final class ToolShortcuts {
    private let defaultsKey: String
    private let store: UserDefaults
    private(set) var keys: [ToolID: String]

    /// Fired after any change, so palettes can refresh their tooltips.
    var onChange: (() -> Void)?

    /// The shipped assignments, taken from each tool's own suggestion.
    static var factory: [ToolID: String] {
        Dictionary(uniqueKeysWithValues: ToolID.allCases.map { ($0, $0.keyEquivalent) })
    }

    init(store: UserDefaults = .standard, defaultsKey: String = "SketchyToolShortcuts") {
        self.store = store
        self.defaultsKey = defaultsKey
        self.keys = ToolShortcuts.factory

        if let saved = store.dictionary(forKey: defaultsKey) as? [String: String] {
            for (raw, key) in saved {
                guard let tool = ToolID(rawValue: raw) else { continue }
                keys[tool] = key
            }
        }
    }

    func key(for tool: ToolID) -> String? {
        let key = keys[tool] ?? ""
        return key.isEmpty ? nil : key
    }

    /// Tools on a given key, in palette order, so cycling is predictable.
    func tools(for key: String) -> [ToolID] {
        let wanted = ToolShortcuts.normalize(key)
        guard !wanted.isEmpty else { return [] }
        return ToolID.paletteOrder.filter { keys[$0] == wanted }
    }

    /// Assigns a key, or clears it when `key` is nil or empty. Keys are single
    /// characters; anything longer is trimmed to its first.
    func setKey(_ key: String?, for tool: ToolID) {
        keys[tool] = ToolShortcuts.normalize(key ?? "")
        save()
    }

    func reset() {
        keys = ToolShortcuts.factory
        store.removeObject(forKey: defaultsKey)
        onChange?()
    }

    /// The tool a key press should switch to, given what is selected now.
    /// Pressing a shared key repeatedly walks the tools that share it.
    func nextTool(for key: String, after current: ToolID) -> ToolID? {
        let matches = tools(for: key)
        guard !matches.isEmpty else { return nil }
        guard let index = matches.firstIndex(of: current) else { return matches[0] }
        return matches[(index + 1) % matches.count]
    }

    static func normalize(_ key: String) -> String {
        String(key.trimmingCharacters(in: .whitespaces).lowercased().prefix(1))
    }

    private func save() {
        var raw: [String: String] = [:]
        for (tool, key) in keys where key != ToolShortcuts.factory[tool] {
            raw[tool.rawValue] = key
        }
        if raw.isEmpty {
            store.removeObject(forKey: defaultsKey)
        } else {
            store.set(raw, forKey: defaultsKey)
        }
        onChange?()
    }
}
