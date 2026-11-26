// The batch actions' rules (`app/lib/ui/batch_actions.dart`). The panel
// parts of `app/test/selection_test.dart` and the bar case of
// `calendar_selection_test.dart` as steps on `BatchSelection` /
// `BatchTagsEditor`; the selection itself (⌘ / Shift, 全选) is tested with
// Selection.swift.

import OpenTodoDomain
import Testing
@testable import OpenTodoUI

private let today = Day(2026, 11, 26) // a Thursday

/// 甲 乙 丙 丁 in the inbox.
private func fourTasks() -> [TodoTask] {
    ["甲", "乙", "丙", "丁"].enumerated().map { i, t in
        TodoTask(id: "t\(i)", listId: inboxListId, title: t)
    }
}

@Suite("desktop: ⌘-click and Shift-click pick tasks; the panel changes them all")
struct PanelChangesThemAll {
    @Test func countsAndPriorityForAll() {
        let tasks = fourTasks()
        let s = BatchSelection(ids: ["t1", "t3"], tasks: tasks)
        #expect(s.count == 2) // 已选择 2 项
        let all = BatchSelection(ids: Set(tasks.map(\.id)), tasks: tasks)
        #expect(all.count == 4)
        #expect(all.priorityTitle == "无优先级")
        #expect(all.setPriority(.high) == .setPriority(ids: ["t0", "t1", "t2", "t3"], .high))
        var high = tasks
        for i in high.indices { high[i].priority = .high }
        #expect(BatchSelection(ids: Set(tasks.map(\.id)), tasks: high).priorityTitle == "高优先级")
    }

    @Test func completeThenDelete() {
        let all = BatchSelection(ids: ["t0", "t1", "t2", "t3"], tasks: fourTasks())
        #expect(all.complete == .complete(ids: ["t0", "t1", "t2", "t3"]))
        let two = BatchSelection(ids: ["t0", "t1"], tasks: fourTasks())
        #expect(two.trash == .trash(ids: ["t0", "t1"]))
    }
}

@Suite("desktop: tags for several tasks: a dash for some, a tick adds to all")
struct TagsForSeveralTasks {
    @Test func dashThenTickAndANewTag() {
        var tasks = fourTasks()
        tasks[0].tags = ["工作"]
        let s = BatchSelection(ids: ["t0", "t1"], tasks: tasks)
        #expect(s.tags == ["工作"]) // the panel's #工作
        var e = BatchTagsEditor(tasks: s.tasks, known: ["工作"])
        #expect(e.state("工作") == nil) // only 甲 has it
        e.toggle("工作")
        #expect(e.state("工作") == true)
        let added1 = e.addNew("本周")
        #expect(added1)
        #expect(e.tags == ["工作", "本周"])
        #expect(e.changes == [
            BatchTagChange(id: "t0", tags: ["工作", "本周"]),
            BatchTagChange(id: "t1", tags: ["工作", "本周"]),
        ])
    }
}

@Suite("narrower window / phone: the bar acts on the picked tasks")
struct BarActsOnPicked {
    @Test func priorityAndCompleteFromTheBar() {
        let s = BatchSelection(ids: ["t0", "t2"], tasks: fourTasks())
        #expect(s.setPriority(.high) == .setPriority(ids: ["t0", "t2"], .high))
        #expect(s.complete == .complete(ids: ["t0", "t2"]))
    }
}

@Suite struct BatchSelectionRules {
    @Test func onlyTasksThatExistAndArentTrashed() {
        var tasks = fourTasks()
        tasks[1].trashedAt = 1
        let s = BatchSelection(ids: ["t0", "t1", "gone"], tasks: tasks)
        #expect(s.count == 3)
        #expect(s.ids == ["t0"])
    }

    @Test func datesKeepEachTasksTime() {
        var tasks = fourTasks()
        tasks[0].dueTime = 9 * 60
        tasks[0].dueDate = today
        let s = BatchSelection(ids: ["t0", "t1"], tasks: tasks)
        #expect(s.setDue(today + 1) == .setDue([
            BatchDueChange(id: "t0", date: today + 1, time: 540),
            BatchDueChange(id: "t1", date: today + 1, time: nil),
        ]))
        // 清除日期: the repo drops the time with the date.
        #expect(s.setDue(nil) == .setDue([
            BatchDueChange(id: "t0", date: nil, time: 540),
            BatchDueChange(id: "t1", date: nil, time: nil),
        ]))
    }

    @Test func dateChoices() {
        #expect(BatchDateChoice.allCases.map(\.title) == ["今天", "明天", "下周一", "选择日期…", "清除日期"])
        #expect(BatchDateChoice.today.day(today: today) == today)
        #expect(BatchDateChoice.tomorrow.day(today: today) == today + 1)
        #expect(BatchDateChoice.nextWeek.day(today: today) == Day(2026, 11, 30))
        #expect(BatchDateChoice.clear.day(today: today) == nil)
    }

    @Test func pinAllIfAnyOpenOneIsntElseUnpinAll() {
        var tasks = fourTasks()
        tasks[0].pinnedAt = 1
        let mixed = BatchSelection(ids: ["t0", "t1", "t2"], tasks: tasks)
        #expect(!mixed.allPinned)
        #expect(mixed.togglePin == .setPinned(ids: ["t1", "t2"], pinned: true))
        tasks[1].pinnedAt = 1
        tasks[2].pinnedAt = 1
        let pinned = BatchSelection(ids: ["t0", "t1", "t2"], tasks: tasks)
        #expect(pinned.allPinned)
        #expect(pinned.togglePin == .setPinned(ids: ["t0", "t1", "t2"], pinned: false))
        // Done tasks are left alone, and don't count.
        tasks[3].status = .done
        let withDone = BatchSelection(ids: ["t0", "t3"], tasks: tasks)
        #expect(withDone.allPinned)
        #expect(withDone.togglePin == .setPinned(ids: ["t0"], pinned: false))
        #expect(withDone.complete == .complete(ids: ["t0"]))
        let onlyDone = BatchSelection(ids: ["t3"], tasks: tasks)
        #expect(!onlyDone.allPinned)
        #expect(onlyDone.togglePin == .setPinned(ids: [], pinned: false))
    }

    @Test func listsAndTags() {
        var tasks = fourTasks()
        tasks[1].listId = "work"
        tasks[0].tags = ["a", "b"]
        tasks[1].tags = ["b", "c"]
        let lists = ["work": TaskList(id: "work", name: "工作")]
        let one = BatchSelection(ids: ["t1"], tasks: tasks)
        #expect(one.listTitle(lists) == "工作")
        #expect(one.listId == "work")
        #expect(BatchSelection(ids: ["t2"], tasks: tasks).listTitle(lists) == "收集箱")
        let two = BatchSelection(ids: ["t0", "t1"], tasks: tasks)
        #expect(two.listTitle(lists) == "2 个清单")
        #expect(two.listId == nil)
        #expect(two.tags == ["a", "b", "c"])
        #expect(two.move(to: "work") == .moveToList(ids: ["t0", "t1"], listId: "work"))
    }

    @Test func prioritiesDiffer() {
        var tasks = fourTasks()
        tasks[0].priority = .low
        let s = BatchSelection(ids: ["t0", "t1"], tasks: tasks)
        #expect(s.priority == nil)
        #expect(s.priorityTitle == "多种优先级")
    }

    @Test func titlesOnePerLine() {
        #expect(BatchSelection(ids: ["t3", "t0"], tasks: fourTasks()).titlesText == "甲\n丁")
    }
}

@Suite struct BatchTagRules {
    @Test func untickingTakesItOffAll() {
        var tasks = fourTasks()
        tasks[0].tags = ["x", "y"]
        tasks[1].tags = ["x"]
        var e = BatchTagsEditor(tasks: [tasks[0], tasks[1]], known: ["x", "y"])
        #expect(e.state("x") == true)
        #expect(e.state("y") == nil)
        e.toggle("x")
        #expect(e.state("x") == false)
        #expect(e.changes == [BatchTagChange(id: "t0", tags: ["y"]), BatchTagChange(id: "t1", tags: [])])
        e.toggle("x") // ticked again: on all
        #expect(e.state("x") == true)
        #expect(e.changes.isEmpty) // both have it already
    }

    @Test func onlyTasksThatChange() {
        var tasks = fourTasks()
        tasks[0].tags = ["x"]
        var e = BatchTagsEditor(tasks: [tasks[0], tasks[1]], known: ["x"])
        e.toggle("x")
        #expect(e.changes == [BatchTagChange(id: "t1", tags: ["x"])])
        #expect(e.action == .setTags([BatchTagChange(id: "t1", tags: ["x"])]))
    }

    @Test func newTagsLoseTheirHashAndBlankIsNothing() {
        var e = BatchTagsEditor(tasks: fourTasks(), known: ["x"])
        let added2 = e.addNew("  ")
        #expect(!added2)
        let added3 = e.addNew("##")
        #expect(!added3)
        let added4 = e.addNew(" ##读书 ")
        #expect(added4)
        #expect(e.tags == ["x", "读书"])
        #expect(e.state("读书") == true)
        let added5 = e.addNew("x")
        #expect(added5) // a known one is just ticked
        #expect(e.tags == ["x", "读书"])
        #expect(e.changes.first?.tags == ["读书", "x"])
    }

    @Test func noChangeWithoutTouching() {
        var tasks = fourTasks()
        tasks[0].tags = ["x"]
        #expect(BatchTagsEditor(tasks: tasks, known: ["x"]).changes.isEmpty)
    }
}

@Test(arguments: BatchDebugState.allCases)
func batchRoutes(_ state: BatchDebugState) {
    #expect(DebugRoute("batch:\(state.rawValue)") == .batch(state.rawValue))
    #expect(DebugRoute("batch:\(state.rawValue)")?.text == "batch:\(state.rawValue)")
}
