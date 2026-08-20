import AppKit
import CoreGraphics

/// One undoable step: a full snapshot of the layer stack.
struct HistorySnapshot {
    struct LayerState {
        let name: String
        let visible: Bool
        let opacity: CGFloat
        let blend: LayerBlendMode
        let image: CGImage?
    }
    let title: String
    let layers: [LayerState]
    let selectedIndex: Int
    let width: Int
    let height: Int

    /// Roughly what this snapshot costs to keep.
    var bytes: Int { width * height * 4 * max(1, layers.count) }
}

final class HistoryManager {
    private(set) var entries: [HistorySnapshot] = []
    private(set) var cursor: Int = -1
    /// Cap so a long session doesn't eat all of RAM.
    var limit: Int = 60
    /// Snapshots are whole-canvas copies, so on a large document a handful of
    /// them outweighs the document itself. Total kept is capped at a share of
    /// the machine rather than a step count alone.
    var byteBudget: Int = Int(ProcessInfo.processInfo.physicalMemory) / 4

    /// Steps currently held, oldest first, and what they cost.
    var estimatedBytes: Int { entries.reduce(0) { $0 + $1.bytes } }

    var canUndo: Bool { cursor > 0 }
    var canRedo: Bool { cursor < entries.count - 1 }
    var currentTitle: String? { cursor >= 0 ? entries[cursor].title : nil }

    var onChange: (() -> Void)?

    func reset(with snapshot: HistorySnapshot) {
        entries = [snapshot]
        cursor = 0
        onChange?()
    }

    func push(_ snapshot: HistorySnapshot) {
        if cursor < entries.count - 1 {
            entries.removeSubrange((cursor + 1)...)
        }
        entries.append(snapshot)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        // Drop the oldest steps until the total fits the budget, always
        // keeping the current state and one step to undo into.
        while entries.count > 2, estimatedBytes > byteBudget {
            entries.removeFirst()
        }
        cursor = entries.count - 1
        onChange?()
    }

    func undo() -> HistorySnapshot? {
        guard canUndo else { return nil }
        cursor -= 1
        onChange?()
        return entries[cursor]
    }

    func redo() -> HistorySnapshot? {
        guard canRedo else { return nil }
        cursor += 1
        onChange?()
        return entries[cursor]
    }

    func jump(to index: Int) -> HistorySnapshot? {
        guard index >= 0, index < entries.count else { return nil }
        cursor = index
        onChange?()
        return entries[cursor]
    }
}
