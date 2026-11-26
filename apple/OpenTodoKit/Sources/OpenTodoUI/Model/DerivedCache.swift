// Values `AppModel` derives from a snapshot, worked out once per snapshot
// instead of on every call: a body asks for `listsById`, `task(_:)` or a
// row's checklist progress once per row, and with thousands of tasks and
// subtasks a fresh scan each time adds up to seconds
// (PerformanceTests: a big list's rows 972 ms → see the commit).
//
// `AppModel.receive(_:)` clears it with each snapshot. Values that also
// depend on the clock keep the `now` they were made at. The accessors
// still read `data` / `now` first, so SwiftUI keeps tracking them.

import OpenTodoData
import OpenTodoDomain

final class DerivedCache {
    var listsById: [String: TaskList]?
    var filtersById: [String: TaskFilter]?
    var filterRules: [String: FilterRule]?
    var sectionsByList: [String: [ListSection]]?
    var tasksById: [String: TodoTask]?
    var checklists: [String: [ChecklistItem]]?
    var tags: [String]?
    var searchData: SearchData?

    /// What also depends on the clock, and the time it was worked out for.
    var clockedAt: LocalDateTime?
    var counts: OpenCounts?
    var sections: [SectionsKey: [TaskSection]] = [:]

    struct SectionsKey: Hashable {
        var view: ViewRef
        var prefs: ViewPrefs
        var showsDone: Bool
    }

    /// A new snapshot: everything goes.
    func clear() {
        listsById = nil
        filtersById = nil
        filterRules = nil
        sectionsByList = nil
        tasksById = nil
        checklists = nil
        tags = nil
        searchData = nil
        clearClocked()
    }

    /// The clock-dependent values, if they were made at another time.
    func clocked(at now: LocalDateTime) {
        if clockedAt != now {
            clearClocked()
            clockedAt = now
        }
    }

    private func clearClocked() {
        clockedAt = nil
        counts = nil
        sections = [:]
    }

    /// The value in `slot`, made with `make` the first time.
    func memo<T>(_ slot: ReferenceWritableKeyPath<DerivedCache, T?>, _ make: () -> T) -> T {
        if let v = self[keyPath: slot] { return v }
        let v = make()
        self[keyPath: slot] = v
        return v
    }
}
