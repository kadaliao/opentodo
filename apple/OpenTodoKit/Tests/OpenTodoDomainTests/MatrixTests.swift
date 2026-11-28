// The four quadrants (效率模块). New in the Swift version, no Dart
// counterpart.

import Foundation
import Testing
@testable import OpenTodoDomain

private let mNow = LocalDateTime(2026, 11, 26, 10, 0)
private let mToday = mNow.day

@Suite("Matrix")
struct MatrixTests {
    @Test func defaultsGoByPriority() {
        let p = MatrixPrefs.standard
        #expect(p.quadrants.map(\.name) == ["重要且紧急", "重要不紧急", "不重要但紧急", "不重要不紧急"])
        #expect(p.quadrants.map { $0.filterRule.valuesOf(.priority) } == [["high"], ["medium"], ["low"], ["none"]])
        #expect(MatrixPrefs.storageKey == "matrix.prefs")
    }

    @Test func tasksGoToTheirQuadrant() {
        let tasks = [
            TodoTask(id: "h", priority: .high),
            TodoTask(id: "m", priority: .medium),
            TodoTask(id: "l", priority: .low),
            TodoTask(id: "n"),
            TodoTask(id: "done", priority: .high, status: .done),
            TodoTask(id: "wont", priority: .high, status: .wontDo),
            TodoTask(id: "trashed", priority: .high, trashedAt: 1),
            TodoTask(id: "deleted", priority: .high, deletedAt: 1),
        ]
        let cells = matrixCells(tasks, now: mNow)
        #expect(cells.map(\.index) == [0, 1, 2, 3])
        #expect(cells.map { $0.tasks.map(\.id) } == [["h"], ["m"], ["l"], ["n"]])
        #expect(cells[0].name == "重要且紧急")
    }

    @Test func eachQuadrantSortsLikeAListByDate() {
        let tasks = [
            TodoTask(id: "nodate", priority: .high),
            TodoTask(id: "later", priority: .high, dueDate: mToday + 3),
            TodoTask(id: "timed", priority: .high, dueDate: mToday, dueTime: 600),
            TodoTask(id: "allday", priority: .high, dueDate: mToday),
            TodoTask(id: "pinned", priority: .high, dueDate: mToday + 9, pinnedAt: 1),
        ]
        #expect(matrixCells(tasks, now: mNow)[0].tasks.map(\.id) == ["pinned", "allday", "timed", "later", "nodate"])
    }

    @Test func firstMatchWinsAndUnmatchedAreHidden() {
        let urgent = FilterRule(conditions: [FilterCondition(.date, ["overdue", "today"])])
        let prefs = MatrixPrefs(quadrants: [
            MatrixQuadrant(name: "急", rule: urgent),
            MatrixQuadrant(name: "高", rule: FilterRule(conditions: [FilterCondition(.priority, ["high"])])),
            MatrixQuadrant(name: "工作", rule: FilterRule(conditions: [FilterCondition(.list, ["work"])])),
            MatrixQuadrant(name: "标签", rule: FilterRule(conditions: [FilterCondition(.tag, ["读书"])])),
        ])
        let tasks = [
            TodoTask(id: "a", priority: .high, dueDate: mToday),
            TodoTask(id: "b", priority: .high),
            TodoTask(id: "c", listId: "work", priority: .high),
            TodoTask(id: "d", listId: "work", tags: ["读书"]),
            TodoTask(id: "e", tags: ["读书"]),
            TodoTask(id: "f", dueDate: mToday - 1),
            TodoTask(id: "none", priority: .low),
        ]
        #expect(matrixCells(tasks, prefs: prefs, now: mNow).map { $0.tasks.map(\.id) } == [["f", "a"], ["b", "c"], ["d"], ["e"]])
    }

    @Test func prefsJsonRoundTrip() {
        let p = MatrixPrefs(quadrants: [
            MatrixQuadrant(name: "A", rule: FilterRule(matchAll: false, conditions: [FilterCondition(.tag, ["x"], exclude: true)])),
        ] + MatrixPrefs.defaultQuadrants.dropFirst())
        #expect(MatrixPrefs.decode(p.json) == p)
        #expect(MatrixPrefs.decode(p.json).quadrants[0].filterRule.matchAll == false)
    }

    @Test func prefsFillWhatIsMissing() {
        #expect(MatrixPrefs.decode(nil) == .standard)
        #expect(MatrixPrefs.decode("[1,2]") == .standard)
        #expect(MatrixPrefs.decode("{}") == .standard)
        let p = MatrixPrefs.decode(#"{"quadrants":[{"name":"今天","rule":"{\"match\":\"all\",\"conditions\":[{\"field\":\"date\",\"values\":[\"today\"]}]}"},{"rule":7},{"name":"x"},{},{"name":"extra"}]}"#)
        #expect(p.quadrants.count == 4)
        #expect(p.quadrants[0].name == "今天" && p.quadrants[0].filterRule.valuesOf(.date) == ["today"])
        #expect(p.quadrants[1] == MatrixPrefs.defaultQuadrants[1])
        #expect(p.quadrants[2].name == "x" && p.quadrants[2].rule == MatrixPrefs.defaultQuadrants[2].rule)
        #expect(p.quadrants[3] == MatrixPrefs.defaultQuadrants[3])
        // An unreadable rule matches everything, like an empty filter.
        let bad = MatrixPrefs(quadrants: [MatrixQuadrant(name: "?", rule: "nonsense")])
        #expect(matrixCells([TodoTask(id: "t")], prefs: bad, now: mNow)[0].tasks.count == 1)
    }

    @Test func droppingTakesWhatTheRuleAsksFor() {
        let task = TodoTask(id: "t", listId: "home", sectionId: "s", priority: .low, dueDate: mToday + 5, dueTime: 600, duration: 60, tags: ["a"])
        let q0 = MatrixPrefs.standard.quadrants[0]
        let moved = movedIntoQuadrant(task, q0, today: mToday)
        #expect(moved.priority == .high)
        var same = moved
        same.priority = task.priority
        #expect(same == task) // nothing else changed
        #expect(movedIntoQuadrant(task, MatrixPrefs.standard.quadrants[3], today: mToday).priority == Priority.none)

        let rule = FilterRule(conditions: [
            FilterCondition(.list, ["work"]),
            FilterCondition(.date, ["tomorrow"]),
            FilterCondition(.tag, ["b"]),
            FilterCondition(.priority, ["high", "medium"]), // two: left alone
        ])
        let m = movedIntoQuadrant(task, MatrixQuadrant(name: "", rule: rule), today: mToday)
        #expect(m.listId == "work" && m.sectionId == nil)
        #expect(m.dueDate == mToday + 1 && m.dueTime == 600 && m.duration == 60)
        #expect(m.tags == ["a", "b"])
        #expect(m.priority == .low)
        // The tag isn't added twice; the same list keeps its section.
        let again = movedIntoQuadrant(m, MatrixQuadrant(name: "", rule: FilterRule(conditions: [FilterCondition(.tag, ["b"]), FilterCondition(.list, ["work"])])), today: mToday)
        #expect(again.tags == ["a", "b"])
        let kept = movedIntoQuadrant(task, MatrixQuadrant(name: "", rule: FilterRule(conditions: [FilterCondition(.list, ["home"])])), today: mToday)
        #expect(kept.sectionId == "s")
    }

    @Test func anyOfRulesChangeNothing() {
        let task = TodoTask(id: "t", priority: .low)
        let rule = FilterRule(matchAll: false, conditions: [FilterCondition(.priority, ["high"])])
        #expect(movedIntoQuadrant(task, MatrixQuadrant(name: "", rule: rule), today: mToday) == task)
    }
}


@Suite("Matrix manual order")
struct MatrixManualOrderTests {
    @Test("自定义 order is kept in the prefs and sorts by sortOrder; older prefs read as by time")
    func manual() {
        let now = LocalDateTime(Day(2026, 11, 28), minute: 600)
        let a = TodoTask(id: "a", listId: "L", title: "a", priority: .high, dueDate: Day(2026, 11, 29), sortOrder: 1)
        let b = TodoTask(id: "b", listId: "L", title: "b", priority: .high, dueDate: Day(2026, 11, 28), sortOrder: 2)
        #expect(matrixCells([a, b], now: now)[0].tasks.map(\.id) == ["b", "a"])
        let manual = MatrixPrefs(manualOrder: true)
        #expect(matrixCells([a, b], prefs: manual, now: now)[0].tasks.map(\.id) == ["a", "b"])
        #expect(MatrixPrefs.decode(manual.json).manualOrder)
        #expect(!MatrixPrefs.decode(MatrixPrefs().json).manualOrder)
        #expect(!MatrixPrefs.decode(#"{"quadrants":[]}"#).manualOrder)
    }
}
