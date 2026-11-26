// Ported from `app/test/pin_sort_test.dart`, the parts that test pure
// functions. Left to others: "pinning is stored and synced…" (TaskRepo and
// the sync codec: data layer) and "view preferences read what earlier
// versions stored" (`ViewPrefs` in `state/providers.dart`: UI state).

import Testing
@testable import OpenTodoDomain

private func pinned(_ t: TodoTask, _ at: Int) -> TodoTask {
    var t = t
    t.pinnedAt = at
    return t
}

@Suite("pin and sort")
struct PinSortTests {
    @Test("pinned tasks come first in a list, a section, a day, a tag")
    func pinnedFirst() {
        let tasks = [
            makeTask("一", listId: "w"),
            makeTask("二", listId: "w"),
            pinned(makeTask("钉住", listId: "w"), 1),
            makeTask("今天早", due: "2026-11-15", time: 8 * 60, tags: ["t"]),
            pinned(makeTask("今天钉住", due: "2026-11-15", time: 20 * 60, tags: ["t"]), 1),
            pinned(makeTask("做完的钉住", listId: "w", status: .done, completedAt: 9), 1),
        ]
        #expect(shape(buildSections(view: .list("w"), tasks: tasks, lists: [:], now: testNow)) == [
            sec(nil, ["钉住", "二", "一"]),
            sec("已完成", ["做完的钉住"]),
        ])
        let today = buildSections(view: .smart(.today), tasks: tasks, lists: [:], now: testNow)
        #expect(today.first?.tasks.map(\.title) == ["今天钉住", "今天早"])
        #expect(today.first?.day == Day(2026, 11, 15))
        let byTag = buildSections(view: .tag("t"), tasks: tasks, lists: [:], now: testNow)
        #expect(byTag.first?.tasks.map(\.title) == ["今天钉住", "今天早"])
    }

    @Test("a list can be ordered by date or priority instead of by hand")
    func listSorts() {
        let tasks = [
            makeTask("无日期高", listId: "w", priority: .high),
            makeTask("后天", listId: "w", due: "2026-11-17"),
            makeTask("明天中", listId: "w", due: "2026-11-16", priority: .medium),
            makeTask("明天低", listId: "w", due: "2026-11-16", priority: .low),
        ]
        func order(_ sort: TaskSort) -> [String] {
            let s = buildSections(view: .list("w"), tasks: tasks, lists: [:], now: testNow, sort: sort)
            #expect(s.count == 1)
            return s.first?.tasks.map(\.title) ?? []
        }
        #expect(order(.manual) == ["明天低", "明天中", "后天", "无日期高"]) // newest first
        #expect(order(.due) == ["明天中", "明天低", "后天", "无日期高"])
        #expect(order(.priority) == ["无日期高", "明天中", "明天低", "后天"])
        // A to Z in pinyin: hou, mingtiandi, mingtianzhong, wu.
        #expect(order(.title) == ["后天", "明天低", "明天中", "无日期高"])
        let s = buildSections(view: .list("w"), tasks: tasks, lists: [:], now: testNow, sort: .due)
        #expect(s.count == 1 && !s[0].manualOrder)
        let manual = buildSections(view: .list("w"), tasks: tasks, lists: [:], now: testNow)
        #expect(manual.count == 1 && manual[0].manualOrder)
    }

    @Test("overdue has no day to drop onto; every day of 最近7天 has one, empty or not")
    func emptyDays() {
        let tasks = [makeTask("过期", due: "2026-11-10"), makeTask("后天", due: "2026-11-17")]
        let s = buildSections(view: .smart(.next7), tasks: tasks, lists: [:], now: testNow)
        #expect(s.map(\.day) == [nil] + (15...21).map { Day(2026, 11, $0) })
        #expect(s.map(\.tasks.count) == [1, 0, 0, 1, 0, 0, 0, 0])
        // 今天 with only overdue tasks still has today to drag them onto.
        let today = buildSections(view: .smart(.today), tasks: tasks, lists: [:], now: testNow)
        #expect(today.map(\.day) == [nil, Day(2026, 11, 15)])
        #expect(today.map(\.tasks.count) == [1, 0])
        // Nothing at all: no sections, so the empty state shows. Only
        // finished ones: nothing to drag, so no empty days either.
        #expect(buildSections(view: .smart(.next7), tasks: [], lists: [:], now: testNow).isEmpty)
        let done = buildSections(
            view: .smart(.today),
            tasks: [makeTask("做完了", due: "2026-11-15", status: .done, completedAt: 1)],
            lists: [:],
            now: testNow
        )
        #expect(done.map(\.title) == ["已完成"])
    }
}
