// The task list's own state on this window: which groups are folded,
// whether 已完成 shows, and requests for the quick-add field to take
// focus. Kept per view (`ViewRef.description`), for the session only.

import Observation
import OpenTodoDomain

@Observable
public final class TaskListState {
    /// Groups the person folded or unfolded, by "view/section id"; the
    /// others follow `collapsedByDefault`.
    private var toggled: [String: Bool] = [:]
    /// Views where the person hid 已完成.
    private var hidingDone: Set<String> = []
    /// Bumped by 新建任务 (⌘N) so the field takes focus.
    public private(set) var quickAddRequests = 0

    public init() {}

    public func isFolded(_ section: TaskSection, in view: ViewRef) -> Bool {
        toggled["\(view)/\(section.id)"] ?? section.collapsedByDefault
    }

    public func setFolded(_ folded: Bool, _ section: TaskSection, in view: ViewRef) {
        toggled["\(view)/\(section.id)"] = folded
    }

    public func showsDone(_ view: ViewRef) -> Bool { !hidingDone.contains(view.description) }

    public func setShowsDone(_ shows: Bool, _ view: ViewRef) {
        if shows { hidingDone.remove(view.description) } else { hidingDone.insert(view.description) }
    }

    public func focusQuickAdd() { quickAddRequests += 1 }

    /// Text for the quick-add field to start with (`-OTQuickAdd`); taken once.
    public var prefill: String?

    public func takePrefill() -> String? {
        defer { prefill = nil }
        return prefill
    }
}
