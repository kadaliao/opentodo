// The cases of `app/test/board_ui_test.dart`, as drags through the drop
// geometry: the lists and boards are laid out on paper (`listSlots`,
// `boardSlots`, the same places the views register), the pointer lands on
// a header or a row, and what the drop comes to is applied to the tasks the
// way TaskRepo.dropInto does. Database and widget plumbing stay with the
// Dart tests; the board's and lists' own behaviour is all here.

import CoreGraphics
import OpenTodoDomain
import SwiftUI
import Testing
@testable import OpenTodoUI

private let work = "work"
private let now = LocalDateTime(Day(2026, 11, 26), minute: 10 * 60)
private let today = now.day

/// 甲, 乙, 丙 in 工作, 丙 newest and so on top.
private func threeTasks() -> [TodoTask] {
    [
        TodoTask(id: "甲", listId: work, title: "甲", sortOrder: 0, createdAt: 1),
        TodoTask(id: "乙", listId: work, title: "乙", sortOrder: -1024, createdAt: 2),
        TodoTask(id: "丙", listId: work, title: "丙", sortOrder: -2048, createdAt: 3),
    ]
}

private func section(_ id: String, _ name: String, _ order: Double) -> ListSection {
    ListSection(id: id, listId: work, name: name, sortOrder: order, createdAt: Int(order))
}

/// A drag space on paper: where each header, row and column is.
private struct Paper {
    var slots: [DropSlot] = []
    var frames: [String: CGRect] = [:]

    func frame(_ name: String) -> CGRect {
        guard let f = frames[name] else { Issue.record("nothing called \(name)"); return .zero }
        return f
    }

    /// The pointer at `name`'s middle, moved by `dx`, `dy`.
    func at(_ name: String, dx: CGFloat = 0, dy: CGFloat = 0) -> CGPoint {
        let f = frame(name)
        return CGPoint(x: f.midX + dx, y: f.midY + dy)
    }

    func hover(_ item: DragItem, _ p: CGPoint) -> DropHover? { resolveDrop(item, at: p, in: slots) }

    func drop(_ item: DragItem, _ p: CGPoint) -> DropOutcome? { hover(item, p)?.outcome(for: item) }
}

/// A task list as the list view lays it out: a 30-point header for a
/// titled group, then 40-point rows; a list's own section headers also
/// take sections.
private func listSlots(_ sections: [TaskSection], listSections: [ListSection] = []) -> Paper {
    var paper = Paper()
    var y: CGFloat = 0
    for s in sections {
        let drop = GroupDrop(s)
        if let title = s.title {
            let f = CGRect(x: 0, y: y, width: 400, height: 30)
            paper.frames[title] = f
            if let drop { paper.slots.append(DropSlot(id: "head-\(s.id)", frame: f, kind: .taskArea(drop, index: 0))) }
            if let ls = s.listSection {
                paper.slots.append(DropSlot(id: "section-\(ls.id)", frame: f, kind: .section(ls, among: listSections, axis: .vertical)))
            }
            y += 30
        }
        for (i, t) in s.tasks.enumerated() {
            let f = CGRect(x: 0, y: y, width: 400, height: 40)
            paper.frames[t.title] = f
            if let drop { paper.slots.append(DropSlot(id: "row-\(t.id)", frame: f, kind: .taskRow(drop, index: i))) }
            y += 40
        }
    }
    return paper
}

/// A board as BoardView lays it out: 272-point columns 12 apart, a
/// 40-point top, 40-point cards 8 apart, then the end space.
private func boardSlots(_ columns: [BoardColumn], sort: TaskSort = .manual) -> Paper {
    var paper = Paper()
    let sections = BoardLayout.sections(columns)
    for (c, column) in columns.enumerated() {
        let x = CGFloat(c) * 284
        let group = BoardLayout.drop(column, listId: work, sort: sort)
        let key = BoardLayout.key(column)
        let head = CGRect(x: x, y: 0, width: 272, height: 40)
        paper.frames[column.group.title] = head
        paper.slots.append(DropSlot(id: "head-\(key)", frame: head, kind: .taskArea(group, index: 0)))
        var y: CGFloat = 40
        for (i, t) in column.group.tasks.enumerated() {
            let card = CGRect(x: x + 8, y: y, width: 256, height: 40)
            paper.frames[t.title] = card
            paper.slots.append(DropSlot(id: "row-\(t.id)", frame: card.insetBy(dx: 0, dy: -4), kind: .taskRow(group, index: i)))
            y += 48
        }
        let end = CGRect(x: x + 8, y: y, width: 256, height: column.group.tasks.isEmpty ? 80 : 40)
        paper.frames["end:\(column.group.title)"] = end
        paper.slots.append(DropSlot(id: "end-\(key)", frame: end, kind: .taskArea(group, index: column.group.tasks.count)))
        if let s = column.group.section {
            paper.slots.append(DropSlot(
                id: "column-\(s.id)", frame: CGRect(x: x - 6, y: 0, width: 284, height: 600),
                kind: .section(s, among: sections, axis: .horizontal)
            ))
        }
    }
    return paper
}

/// What TaskRepo does with a drop and with section changes.
private func apply(_ outcome: DropOutcome?, _ tasks: inout [TodoTask], _ sections: inout [ListSection]) {
    switch outcome {
    case .tasks(let plan)?:
        for id in plan.ids {
            guard let i = tasks.firstIndex(where: { $0.id == id }), !plan.target.has(tasks[i]) else { continue }
            switch plan.target {
            case .section(_, let sectionId): tasks[i].sectionId = sectionId
            case .date(let day):
                tasks[i].dueDate = day
                if day == nil { tasks[i].dueTime = nil }
            case .priority(let p): tasks[i].priority = p
            case .list(let listId):
                tasks[i].listId = listId
                tasks[i].sectionId = nil
            case .tag: tasks[i].tags = plan.target.retag(tasks[i].tags)
            case .order: break
            }
        }
        for (id, order) in plan.orders {
            if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].sortOrder = order }
        }
    case .sections(let orders)?:
        apply(.reorder(orders), &tasks, &sections)
    case nil:
        break
    }
}

private func apply(_ action: SectionAction, _ tasks: inout [TodoTask], _ sections: inout [ListSection]) {
    switch action {
    case let .add(listId, name):
        sections.append(ListSection(id: name, listId: listId, name: name, sortOrder: (sections.map(\.sortOrder).max() ?? 0) + 1024))
    case let .rename(id, name):
        if let i = sections.firstIndex(where: { $0.id == id }) { sections[i].name = name }
    case .reorder(let orders):
        for (id, order) in orders {
            if let i = sections.firstIndex(where: { $0.id == id }) { sections[i].sortOrder = order }
        }
    case .delete(let id):
        sections.removeAll { $0.id == id }
        for i in tasks.indices where tasks[i].sectionId == id { tasks[i].sectionId = nil }
    }
}

private func list(
    _ tasks: [TodoTask], _ sections: [ListSection], view: ViewRef = .list(work),
    grouping: TaskGrouping? = nil, sort: TaskSort? = nil, lists: [String: TaskList] = [:]
) -> [TaskSection] {
    buildSections(
        view: view, tasks: tasks, lists: lists, now: now, sectionsByList: [work: sections],
        grouping: grouping, sort: sort, timeZone: TimeZone(identifier: "Asia/Shanghai")!
    )
}

private func task(_ tasks: [TodoTask], _ title: String) -> TodoTask { tasks.first { $0.title == title }! }

private func drag(_ tasks: [TodoTask], _ title: String, picked: [String] = []) -> DragItem {
    .tasks(DraggedTasks(task(tasks, title), picked: picked.map { task(tasks, $0) }))
}

/// Titles of the open tasks shown, in order.
private func shown(_ sections: [TaskSection]) -> [String] {
    sections.filter { !$0.finished }.flatMap { $0.tasks.map(\.title) }
}

private func sectionNames(_ sections: [ListSection]) -> [String] {
    sections.sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
}

// MARK: - board_ui_test.dart

@Test func desktopSectionsInAListDragTasksIntoThemAndAround() {
    var tasks = threeTasks()
    var sections = [section("doing", "进行中", 0)]
    var view = list(tasks, sections)
    #expect(view.map(\.title) == ["未分组", "进行中"])

    // 甲 onto the 进行中 header.
    apply(listSlots(view, listSections: sections).drop(drag(tasks, "甲"), listSlots(view).at("进行中")), &tasks, &sections)
    #expect(task(tasks, "甲").sectionId == "doing")

    // 乙 below 甲, in 进行中.
    view = list(tasks, sections)
    apply(listSlots(view).drop(drag(tasks, "乙"), listSlots(view).at("甲", dy: 8)), &tasks, &sections)
    #expect(task(tasks, "乙").sectionId == "doing")
    #expect(task(tasks, "乙").sortOrder > task(tasks, "甲").sortOrder)

    // 丙, the last one without a section, above 甲.
    view = list(tasks, sections)
    apply(listSlots(view).drop(drag(tasks, "丙"), listSlots(view).at("甲", dy: -8)), &tasks, &sections)
    #expect(task(tasks, "丙").sectionId == "doing")
    #expect(task(tasks, "丙").sortOrder < task(tasks, "甲").sortOrder)
    // 未分组 is empty now, so it's gone.
    view = list(tasks, sections)
    #expect(view.map(\.title) == ["进行中"])

    // Rename and delete from the section's ⋯.
    #expect(SectionMenuEntry.entries(index: 0, count: 1) == [.rename, .delete])
    #expect(SectionMenuEntry.delete.label(horizontal: false) == "删除分组")
    apply(.rename(sectionId: "doing", name: sectionName(" 本周 ")!), &tasks, &sections)
    #expect(list(tasks, sections).map(\.title) == ["本周"])
    apply(.delete(sectionId: "doing"), &tasks, &sections)
    #expect(task(tasks, "甲").sectionId == nil)
    view = list(tasks, sections)
    #expect(!view.contains { $0.title == "本周" })
    // The manual order stays: 丙, 甲, 乙.
    #expect(shown(view) == ["丙", "甲", "乙"])
}

@Test func desktopTheBoardColumnsDraggingBetweenThemAddingInOne() {
    var tasks = threeTasks()
    var sections = [section("doing", "进行中", 0)]
    var columns = boardColumns(work, tasks, sections)
    #expect(columns.map(\.group.title) == ["未分组", "进行中"])
    #expect(columns[1].group.tasks.isEmpty) // 拖任务到这里

    // 乙 into the empty column.
    apply(boardSlots(columns).drop(drag(tasks, "乙"), boardSlots(columns).at("end:进行中")), &tasks, &sections)
    #expect(task(tasks, "乙").sectionId == "doing")

    // Add 丁 in 进行中 with its own field.
    columns = boardColumns(work, tasks, sections)
    let add = BoardLayout.quickAdd(" 丁 ", in: columns[1], listId: work)
    #expect(add == BoardQuickAdd(text: "丁", listId: work, sectionId: "doing"))
    #expect(BoardLayout.quickAdd("  ", in: columns[1], listId: work) == nil)
    tasks.append(TodoTask(id: "丁", listId: add!.listId, sectionId: add!.sectionId, title: add!.text))

    // Ticking a card off moves it under 已完成 in its column.
    tasks[tasks.firstIndex { $0.title == "丁" }!].status = .done
    columns = boardColumns(work, tasks, sections)
    #expect(columns[1].group.tasks.map(\.title) == ["乙"])
    #expect(columns[1].done.map(\.title) == ["丁"])
}

@Test func desktopIn最近7天DragTasksToAnotherDayAnEmptyOneTooTimesStay() {
    var tasks = [
        TodoTask(id: "a", title: "晚上开会", dueDate: today, dueTime: 23 * 60 + 30),
        TodoTask(id: "b", title: "早上跑步", dueDate: today, dueTime: 7 * 60),
        TodoTask(id: "c", title: "后天的", dueDate: today + 2),
    ]
    var sections: [ListSection] = []
    var view = list(tasks, sections, view: .smart(.next7))
    // Every day of the seven shows, so the empty ones take drops too.
    #expect(view.count == 7)
    #expect(view.filter { $0.title?.contains("月") == true }.count == 5)

    let inTwo = daySectionTitle(today + 2, today: today), inThree = daySectionTitle(today + 3, today: today)
    apply(listSlots(view).drop(drag(tasks, "晚上开会"), listSlots(view).at(inTwo)), &tasks, &sections)
    #expect(task(tasks, "晚上开会").dueDate == today + 2)
    #expect(task(tasks, "晚上开会").dueTime == 23 * 60 + 30)

    // Two picked go together onto an empty day, each keeping its time.
    view = list(tasks, sections, view: .smart(.next7))
    let item = drag(tasks, "早上跑步", picked: ["早上跑步", "晚上开会"])
    apply(listSlots(view).drop(item, listSlots(view).at(inThree)), &tasks, &sections)
    let days: [Day?] = ["晚上开会", "早上跑步"].map { task(tasks, $0).dueDate }
    let times: [Int?] = ["晚上开会", "早上跑步"].map { task(tasks, $0).dueTime }
    #expect(days == [today + 3, today + 3])
    #expect(times == [23 * 60 + 30, 7 * 60])
    #expect(task(tasks, "后天的").dueDate == today + 2)
}

@Test func desktopPickedTasksDragTogetherSectionsDragByTheirHeaders() {
    var tasks = threeTasks()
    var sections = [section("doing", "进行中", 0), section("later", "稍后", 1024)]

    // Pick 甲 and 丙; drag 甲 onto 进行中: both go, 丙 still above 甲.
    var view = list(tasks, sections)
    let item = drag(tasks, "甲", picked: ["丙", "甲"])
    apply(listSlots(view).drop(item, listSlots(view).at("进行中")), &tasks, &sections)
    let moved: [String?] = ["甲", "丙", "乙"].map { task(tasks, $0).sectionId }
    #expect(moved == ["doing", "doing", nil])
    #expect(task(tasks, "丙").sortOrder < task(tasks, "甲").sortOrder)

    // 稍后 dragged onto the top of 进行中 goes before it.
    #expect(sectionNames(sections) == ["进行中", "稍后"])
    view = list(tasks, sections)
    let paper = listSlots(view, listSections: sections)
    let hover = paper.hover(.section(sections[1]), paper.at("进行中", dy: -6))
    #expect(hover?.indicator == .line(CGPoint(x: 0, y: paper.frame("进行中").minY), CGPoint(x: 400, y: paper.frame("进行中").minY)))
    apply(paper.drop(.section(sections[1]), paper.at("进行中", dy: -6)), &tasks, &sections)
    #expect(sectionNames(sections) == ["稍后", "进行中"])
    #expect(list(tasks, sections).map(\.title) == ["未分组", "稍后", "进行中"])

    // On the board, columns move the same way: 稍后 to the right of 进行中.
    let columns = boardColumns(work, tasks, sections)
    let board = boardSlots(columns)
    let later = sections.first { $0.name == "稍后" }!
    apply(board.drop(.section(later), board.at("进行中", dx: 100)), &tasks, &sections)
    #expect(sectionNames(sections) == ["进行中", "稍后"])
}

@Test func desktopPinFromTheMenuOrderByPriorityWhereDropsOnlyChangeSection() {
    var tasks = threeTasks()
    var sections: [ListSection] = []
    #expect(shown(list(tasks, sections)) == ["丙", "乙", "甲"]) // newest first

    // Pin 甲: it goes to the top.
    tasks[tasks.firstIndex { $0.title == "甲" }!].pinnedAt = 1
    var view = list(tasks, sections)
    #expect(shown(view) == ["甲", "丙", "乙"])

    // Dragging an unpinned task above the pinned one keeps it below.
    apply(listSlots(view).drop(drag(tasks, "乙"), listSlots(view).at("甲", dy: -8)), &tasks, &sections)
    #expect(shown(list(tasks, sections)) == ["甲", "乙", "丙"])

    // Order by priority: 丙 (high) first after the pinned 甲.
    tasks[tasks.firstIndex { $0.title == "丙" }!].priority = .high
    view = list(tasks, sections, sort: .priority)
    #expect(shown(view) == ["甲", "丙", "乙"])

    // A drop within the section doesn't change the order now...
    let before = task(tasks, "乙").sortOrder
    #expect(listSlots(view).hover(drag(tasks, "乙"), listSlots(view).at("丙", dy: -8)) == nil)
    // ...but a drop into another section moves it there, the group lit up.
    apply(.add(listId: work, name: "稍后"), &tasks, &sections)
    view = list(tasks, sections, sort: .priority)
    let paper = listSlots(view)
    let hover = paper.hover(drag(tasks, "乙"), paper.at("稍后"))
    #expect(hover?.indicator == .group(.section(listId: work, sectionId: "稍后")))
    apply(paper.drop(drag(tasks, "乙"), paper.at("稍后")), &tasks, &sections)
    #expect(task(tasks, "乙").sectionId == "稍后")
    #expect(task(tasks, "乙").sortOrder == before)
}

@Test func phoneALongPressWithoutMovingOpensTheMenuWithMovingDrags() {
    // The menu on a long press that doesn't move is the system's context
    // menu (`.contextMenu` beside `.draggable`); the drag is the same as
    // with a mouse.
    var tasks = threeTasks()
    var sections: [ListSection] = []
    let view = list(tasks, sections)
    apply(listSlots(view).drop(drag(tasks, "甲"), listSlots(view).at("丙", dy: -10)), &tasks, &sections)
    #expect(task(tasks, "甲").sortOrder < task(tasks, "丙").sortOrder)
}

@Test func desktopGroupAListByPriorityTagOrDateADropTakesOnItsGroup() {
    var tasks = threeTasks()
    var sections: [ListSection] = []
    tasks[tasks.firstIndex { $0.title == "丙" }!].priority = .high
    tasks[tasks.firstIndex { $0.title == "乙" }!].tags = ["家务", "周末"]
    tasks[tasks.firstIndex { $0.title == "甲" }!].dueDate = today
    tasks[tasks.firstIndex { $0.title == "甲" }!].dueTime = 9 * 60

    var view = list(tasks, sections, grouping: .priority)
    #expect(view.map(\.title) == ["高优先级", "无优先级"])
    apply(listSlots(view).drop(drag(tasks, "甲"), listSlots(view).at("高优先级")), &tasks, &sections)
    #expect(task(tasks, "甲").priority == .high)
    #expect(list(tasks, sections, grouping: .priority).map(\.title) == ["高优先级", "无优先级"]) // 乙 is still there

    // By tag: filed under the first one; a drop swaps that one.
    view = list(tasks, sections, grouping: .tag)
    #expect(view.map(\.title) == ["家务", "无标签"])
    apply(listSlots(view).drop(drag(tasks, "丙"), listSlots(view).at("家务")), &tasks, &sections)
    #expect(task(tasks, "丙").tags == ["家务"])
    view = list(tasks, sections, grouping: .tag)
    apply(listSlots(view).drop(drag(tasks, "乙"), listSlots(view).at("无标签")), &tasks, &sections)
    #expect(task(tasks, "乙").tags.isEmpty)

    // By date: a day keeps the time; 无日期 clears the date.
    view = list(tasks, sections, grouping: .date)
    let todayTitle = daySectionTitle(today, today: today)
    #expect(view.map(\.title).contains(todayTitle))
    #expect(view.map(\.title).contains("无日期"))
    apply(listSlots(view).drop(drag(tasks, "乙"), listSlots(view).at(todayTitle)), &tasks, &sections)
    #expect(task(tasks, "乙").dueDate == today)
    view = list(tasks, sections, grouping: .date)
    apply(listSlots(view).drop(drag(tasks, "甲"), listSlots(view).at("无日期")), &tasks, &sections)
    #expect(task(tasks, "甲").dueDate == nil)

    // Sort by tag while grouped by date: still only the group counts.
    view = list(tasks, sections, grouping: .date, sort: .tag)
    #expect(view.allSatisfy { !$0.manualOrder })
    // (Adding a section switching the list back to its sections is the
    // view preferences' business, not the drag's.)
}

@Test func desktop今天GroupedByListOrNotAtAllDropOnAListMovesTheTask() {
    var tasks = [
        TodoTask(id: "a", listId: inboxListId, title: "买菜", dueDate: today),
        TodoTask(id: "b", listId: work, title: "写报告", dueDate: today),
    ]
    var sections: [ListSection] = []
    let lists = [work: TaskList(id: work, name: "工作")]
    // 今天 offers 自定义 (dragging a task's handle switches to it), but
    // sorts by time unless asked.
    #expect(sortsFor(.smart(.today)).contains(.manual) && sortsFor(.smart(.today)).first == .due)

    var view = list(tasks, sections, view: .smart(.today), grouping: .list, lists: lists)
    #expect(view.map(\.title) == ["收集箱", "工作"])
    apply(listSlots(view).drop(drag(tasks, "买菜"), listSlots(view).at("工作")), &tasks, &sections)
    #expect(task(tasks, "买菜").listId == work)
    #expect(!list(tasks, sections, view: .smart(.today), grouping: .list, lists: lists).contains { $0.title == "收集箱" })

    // Not grouped: no headers, and nothing to drop into.
    view = list(tasks, sections, view: .smart(.today), grouping: TaskGrouping.none, lists: lists)
    #expect(view.allSatisfy { $0.title == nil })
    #expect(view.compactMap(GroupDrop.init).isEmpty)
}
