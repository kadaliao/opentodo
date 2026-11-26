// Several tasks picked at once (多选), ported from the logic of
// `app/lib/state/selection.dart`: ⌘-click to pick or unpick, Shift-click for
// a range in the order shown, select all, clear, and on a touch screen a
// picking mode where a tap picks. A plain value: the list, the board, the
// timeline and the calendar each keep one in their state and pass it in.
//
// The Dart notifier also clears itself when the view or module changes;
// that is the state layer's job (reset the value when the view changes).

/// The tasks picked, and where a Shift-click range starts.
public struct TaskSelection: Sendable, Hashable {
    public var ids: Set<String>
    /// Where a Shift-click range starts: the task picked last.
    public var anchor: String?

    public init(_ ids: Set<String> = [], anchor: String? = nil) {
        self.ids = ids
        self.anchor = anchor
    }

    public var active: Bool { !ids.isEmpty }

    public func contains(_ id: String) -> Bool { ids.contains(id) }

    /// Starts picking with `id` (from a task's menu: 多选).
    public mutating func start(_ id: String) {
        self = TaskSelection([id], anchor: id)
    }

    /// Adds `id` or takes it out. Starting from nothing, the task open in
    /// the detail (`current`) comes along, as a ⌘-click does elsewhere.
    public mutating func toggle(_ id: String, current: String? = nil) {
        var ids = self.ids
        if ids.isEmpty, let current, current != id { ids.insert(current) }
        if ids.remove(id) == nil { ids.insert(id) }
        self = TaskSelection(ids, anchor: id)
    }

    /// Adds every task from the anchor (or `current`) to `id`, in the order
    /// shown (`order`). When either end isn't in `order`, toggles `id`.
    public mutating func extend(to id: String, in order: [String], current: String? = nil) {
        guard let from = order.firstIndex(of: anchor ?? current ?? id), let to = order.firstIndex(of: id) else {
            toggle(id, current: current)
            return
        }
        let range = order[min(from, to)...max(from, to)]
        self = TaskSelection(ids.union(range), anchor: anchor ?? order[from])
    }

    public mutating func selectAll(_ order: [String]) {
        self = TaskSelection(Set(order), anchor: order.first)
    }

    public mutating func clear() {
        self = TaskSelection()
    }
}

/// The keys held during a click: ⌘ (Ctrl elsewhere) and Shift.
public struct TapModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = TapModifiers(rawValue: 1)
    public static let shift = TapModifiers(rawValue: 2)
}

/// What a click or tap on a task in a list, on the board, the timeline or
/// the calendar does (Dart's `tapTask`): with ⌘ adds it to the selection
/// or takes it out; with Shift picks everything up to it in `order`; while
/// picking on a touch screen a tap picks or unpicks; otherwise it stops
/// picking and opens the task. `current` is the task open in the detail.
/// Returns the task to open, if any.
@discardableResult
public func tapTask(
    _ id: String,
    selection: inout TaskSelection,
    order: [String],
    current: String?,
    modifiers: TapModifiers = [],
    touch: Bool
) -> String? {
    if touch && selection.active {
        selection.toggle(id)
    } else if modifiers.contains(.command) {
        selection.toggle(id, current: current)
    } else if modifiers.contains(.shift) {
        selection.extend(to: id, in: order, current: current)
    } else {
        if selection.active { selection.clear() }
        return id
    }
    return nil
}
