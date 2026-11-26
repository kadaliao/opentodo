// Ported from `app/test/sections_test.dart`, the parts that test pure
// functions. The Dart tests build their data through `TaskRepo`; here the
// same tasks and sections are made directly. Left to the data layer:
// "deleting a section keeps its tasks; moving a task to another list leaves
// its section", "deleting a list deletes its sections", and the repo checks
// inside the first test (sections numbered per list, `dirty` after a move).

import Testing
@testable import OpenTodoDomain

private func titlesOf(_ ts: [TodoTask]) -> [String] { ts.map(\.title) }

private func placed(_ t: TodoTask, _ sectionId: String?, _ order: Double) -> TodoTask {
    var t = t
    t.sectionId = sectionId
    t.sortOrder = order
    return t
}

@Suite("sections")
struct SectionsTests {
    @Test("sections go in order; a list without them has no headers")
    func sectionsInOrder() {
        // Added one after the other, so the later ones come first.
        var tasks = [makeTask("甲", listId: "work"), makeTask("乙", listId: "work")]
        var s = buildSections(view: .list("work"), tasks: tasks, lists: [:], now: testNow)
        #expect(shape(s) == [sec(nil, ["乙", "甲"])]) // newest first
        #expect(targetKind(s.first?.target) == "SectionTarget")

        let doing = section("doing", "进行中", orderStep, listId: "work")
        let todo = section("todo", "待办", 2 * orderStep, listId: "work")
        let elsewhere = section("other", "别的清单的", orderStep, listId: "home")
        let byList = ["work": [todo, doing], "home": [elsewhere]]
        func build() -> [TaskSection] {
            buildSections(view: .list("work"), tasks: tasks, lists: [:], now: testNow, sectionsByList: byList)
        }
        s = build()
        // Unsectioned tasks first; empty sections still show, to drop into.
        #expect(shape(s) == [
            sec("未分组", ["乙", "甲"]),
            sec("进行中", []),
            sec("待办", []),
        ])
        #expect(s[1].listSection?.id == "doing")

        tasks.append(makeTask("丙", listId: "work", sectionId: "todo"))
        // Drag 甲 above 乙 within 未分组, then 乙 into 进行中.
        let jia = tasks[0], yi = tasks[1]
        let move = planMove([yi.id, jia.id], jia.id, 0) { id in tasks.first { $0.id == id }!.sortOrder }
        tasks[0] = placed(jia, nil, move[jia.id]!)
        tasks[1] = placed(yi, "doing", 0)
        s = build()
        #expect(shape(s) == [
            sec("未分组", ["甲"]),
            sec("进行中", ["乙"]),
            sec("待办", ["丙"]),
        ])

        // Once everything is sorted, 未分组 goes away.
        tasks[0] = placed(tasks[0], "todo", 99_999_999_999_999)
        s = build()
        #expect(shape(s) == [
            sec("进行中", ["乙"]),
            sec("待办", ["丙", "甲"]),
        ])
    }

    @Test("the board: a column per section, finished cards at the bottom of theirs")
    func board() {
        let secs = [section("doing", "进行中", orderStep, listId: "work"), section("done", "完成了", 2 * orderStep, listId: "work")]
        var tasks = [
            makeTask("甲", listId: "work", sectionId: "doing"),
            makeTask("乙", listId: "work", sectionId: "doing"),
            makeTask("丙", listId: "work", status: .done, completedAt: testNowMillis, sectionId: "done"),
            makeTask("别处", listId: "home"),
        ]

        var cols = boardColumns("work", tasks, secs)
        #expect(cols.map(\.group.title) == ["进行中", "完成了"])
        #expect(titlesOf(cols[0].group.tasks) == ["乙", "甲"])
        #expect(titlesOf(cols[1].group.tasks).isEmpty)
        #expect(titlesOf(cols[1].done) == ["丙"])

        // A finished task outside any section brings 未分组 back.
        tasks[0] = placed(tasks[0], nil, 0)
        tasks[0].status = .done
        tasks[0].completedAt = testNowMillis + 1000
        cols = boardColumns("work", tasks, secs)
        #expect(cols.map(\.group.title) == ["未分组", "进行中", "完成了"])
        #expect(titlesOf(cols[0].done) == ["甲"])

        // No sections: one 未分组 column, even when empty.
        cols = boardColumns("empty", tasks, [])
        #expect(cols.map(\.group.title) == ["未分组"])
    }

    @Test("a task whose section is gone, or another list's, is under 未分组")
    func stray() {
        let mine = section("mine", "进行中", 0, listId: "work")
        let stray = makeTask("迷路", listId: "work", sectionId: "elsewhere")
        let placed = makeTask("归位", listId: "work", sectionId: "mine")
        let groups = listGroups([stray, placed], [mine])
        #expect(groups.map { "\($0.title): \(titlesOf($0.tasks).joined())" } == ["未分组: 迷路", "进行中: 归位"])
        #expect(arrangedListId(.smart(.inbox)) == inboxListId)
        #expect(arrangedListId(.smart(.today)) == nil)
        #expect(arrangedListId(.tag("x")) == nil)
    }
}
