// The board and the list's drags in the app: AppModel over a real
// in-memory database and TaskRepo, with the demo data, the clock fixed at
// 2026-11-26 09:41 in Shanghai. What board_ui_test.dart checks through the
// screen, here through what the board and the list hand the model (drop
// plans, quick adds, taps, section actions).

import Foundation
import OpenTodoData
import OpenTodoDomain
import SwiftUI
import Testing
@testable import OpenTodoUI

nonisolated private let tz = TimeZone(identifier: "Asia/Shanghai")!
nonisolated private let now = LocalDateTime(2026, 11, 26, 9, 41)
nonisolated private let today = now.day
private let work = ViewRef.list("work")

private func makeModel() async throws -> AppModel {
    let db = try AppDatabase.inMemory()
    let settings = LocalSettings(db)
    let repo = TaskRepo(db, clock: { now.date(in: tz) }, defaults: settings.defaultsProvider, timeZone: tz)
    try await DemoData.seed(repo, now: now)
    let model = AppModel(repo: repo, settings: settings, now: now)
    model.setWidth(.regular)
    await model.start(clock: false)
    try await waitUntil { model.loaded }
    return model
}

private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<400 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("timed out")
}

/// Waits for the model to have the database's latest snapshot.
private func settle(_ model: AppModel) async throws {
    let data = try await model.database.observeTaskData().first()
    try await waitUntil { model.data == data }
}

private func column(_ m: AppModel, _ name: String) -> BoardColumn {
    m.boardColumns(work).first { $0.group.title == name }!
}

private func drop(_ m: AppModel, _ ids: [String], into column: BoardColumn, at index: Int) async throws {
    let group = BoardLayout.drop(column, listId: "work", sort: m.boardSort(work))
    let lead = m.task(ids[0])!
    let picked = ids.map { m.task($0)! }
    if let plan = group.plan(DraggedTasks(lead, picked: picked), at: index) { await m.dropTasks(plan) }
    try await settle(m)
}

@Suite struct BoardInTheApp {
    @Test func theBoardHasAColumnPerSectionWithItsFinishedOnesBelow() async throws {
        let m = try await makeModel()
        m.settings.setLayout(work, .board)
        #expect(m.prefs(for: work).layoutIn(work) == .board)
        let columns = m.boardColumns(work)
        #expect(columns.map(\.group.title) == ["进行中", "待安排"])
        #expect(columns[0].group.tasks.first?.id == "slides") // pinned first
        #expect(columns.flatMap(\.done).count == 1)
        // A board offers no grouping (its columns are the sections).
        #expect(layouts(for: work) == [.list, .board, .timeline])
    }

    @Test func dragCardsBetweenAndWithinColumns() async throws {
        let m = try await makeModel()
        // 起草明年的 OKR onto the top of 进行中, below the pinned card.
        try await drop(m, ["okr"], into: column(m, "进行中"), at: 0)
        #expect(m.task("okr")?.sectionId == "work-doing")
        let doing = column(m, "进行中").group.tasks.map(\.id)
        #expect(doing.prefix(2) == ["slides", "okr"])
        // Within the column: to the end.
        try await drop(m, ["okr"], into: column(m, "进行中"), at: doing.count)
        #expect(column(m, "进行中").group.tasks.last?.id == "okr")
        // Two picked go together into the empty end of 待安排, in order.
        try await drop(m, ["report", "standup"], into: column(m, "待安排"), at: column(m, "待安排").group.tasks.count)
        #expect(column(m, "待安排").group.tasks.map(\.id).suffix(2) == ["report", "standup"])
    }

    @Test func outOfManualOrderADropOnlyChangesTheColumn() async throws {
        let m = try await makeModel()
        m.settings.setSort(work, .priority)
        #expect(m.boardSort(work) == .priority)
        let before = m.task("review")!.sortOrder
        let doing = BoardLayout.drop(column(m, "进行中"), listId: "work", sort: .priority)
        #expect(doing.plan(DraggedTasks(m.task("review")!), at: 0) == nil) // its own column
        try await drop(m, ["review"], into: column(m, "待安排"), at: 0)
        #expect(m.task("review")?.sectionId == "work-later")
        #expect(m.task("review")?.sortOrder == before)
    }

    @Test func addInAColumnTickOffOpenAndPick() async throws {
        let m = try await makeModel()
        let actions = m.boardActions(work, order: BoardLayout.taskOrder(m.boardColumns(work)))
        // 丁 in 待安排 with its own field.
        let add = try #require(BoardLayout.quickAdd("丁", in: column(m, "待安排"), listId: "work"))
        actions.quickAdd(add)
        try await waitUntil { m.data.tasks.contains { $0.title == "丁" } }
        let ding = try #require(m.data.tasks.first { $0.title == "丁" })
        #expect(ding.sectionId == "work-later" && ding.listId == "work")

        // Ticking it off puts it under 已完成 in its column.
        await m.setDone(ding, true)
        try await settle(m)
        #expect(column(m, "待安排").done.contains { $0.id == ding.id })

        // A click opens; ⌘-click picks (taking the open one along).
        let order = BoardLayout.taskOrder(m.boardColumns(work))
        m.tapTask("okr", modifiers: [], order: order)
        #expect(m.selectedTaskId == "okr")
        #expect(m.boardSelection.isSelected("okr"))
        m.tapTask("onboarding", modifiers: .command, order: order)
        #expect(m.selection.ids == ["okr", "onboarding"])
        #expect(m.boardSelection.picking && m.boardSelection.isSelected("onboarding"))
        #expect(BoardLayout.picked(m.boardColumns(work), m.boardSelection).map(\.id) == ["okr", "onboarding"])
    }

    @Test func sectionsFromTheColumnMenusAndDialogs() async throws {
        let m = try await makeModel()
        // Renaming and deleting ask with the app's own dialogs.
        let doing = m.sectionsByList["work"]!.first { $0.id == "work-doing" }!
        m.ask(.rename(doing))
        #expect(m.present.textPrompt != nil)
        m.present.textPrompt = nil
        m.ask(.delete(doing))
        #expect(m.present.confirm != nil)
        m.present.confirm = nil

        // 右移 from the menu.
        let among = BoardLayout.sections(m.boardColumns(work))
        await m.perform(.reorder(planSectionShift(among, "work-doing", by: 1)))
        try await settle(m)
        #expect(m.boardColumns(work).map(\.group.title) == ["待安排", "进行中"])
        await m.perform(.rename(sectionId: "work-doing", name: "本周"))
        await m.perform(.delete(sectionId: "work-later"))
        try await settle(m)
        #expect(m.boardColumns(work).map(\.group.title) == ["未分组", "本周"])
        #expect(m.task("okr")?.sectionId == nil)
    }

    @Test func addingASectionShowsTheListsSectionsAgain() async throws {
        let m = try await makeModel()
        m.settings.setGrouping(work, .priority)
        await m.perform(.add(listId: "work", name: "下周"))
        try await settle(m)
        #expect(m.prefs(for: work).groupingIn(work) == .sections)
        #expect(m.sections(for: work).contains { $0.title == "下周" })
        // The same through the dialog.
        m.settings.setGrouping(work, .tag)
        m.askAddSection("work")
        m.present.textPrompt?.onSubmit("稍后")
        try await waitUntil { m.sectionsByList["work"]?.contains { $0.name == "稍后" } == true }
        try await waitUntil { m.prefs(for: work).groupingIn(work) == .sections }
    }
}

@Suite struct ListDragInTheApp {
    /// Drops `ids` on the header of the section titled `title` of `view`.
    private func dropOnHeader(_ m: AppModel, _ view: ViewRef, _ ids: [String], _ title: String) async throws {
        let section = try #require(m.sections(for: view).first { $0.title == title })
        let group = try #require(GroupDrop(section))
        let picked = ids.map { m.task($0)! }
        let plan = try #require(group.plan(DraggedTasks(picked[0], picked: picked), at: 0))
        await m.dropTasks(plan)
        try await settle(m)
    }

    @Test func inNext7DaysTasksDropOnAnotherDayKeepingTheirTimes() async throws {
        let m = try await makeModel()
        m.select(.smart(.next7))
        let report = m.task("report")!
        let inThree = daySectionTitle(today + 3, today: today)
        try await dropOnHeader(m, .smart(.next7), ["report", "standup"], inThree)
        #expect(m.task("report")?.dueDate == today + 3)
        #expect(m.task("report")?.dueTime == report.dueTime)
        #expect(m.task("standup")?.dueDate == today + 3)
        // 已过期 takes nothing.
        let overdue = try #require(m.sections(for: .smart(.next7)).first { $0.title == "已过期" })
        #expect(GroupDrop(overdue) == nil)
    }

    @Test func groupedByPriorityTagOrListADropTakesOnTheGroup() async throws {
        let m = try await makeModel()
        m.settings.setGrouping(work, .priority)
        try await dropOnHeader(m, work, ["onboarding"], "高优先级")
        #expect(m.task("onboarding")?.priority == .high)
        m.settings.setGrouping(.smart(.today), .list)
        let other = try #require(m.sections(for: .smart(.today)).first { $0.target != nil && $0.target != .list("work") })
        guard case .list(let otherList)? = other.target else { Issue.record("not a list group"); return }
        try await dropOnHeader(m, .smart(.today), ["report"], other.title!)
        #expect(m.task("report")?.listId == otherList)
        #expect(m.task("report")?.sectionId == nil)
    }

    @Test func thePickedRowsInTheOrderShownAndTheRowsToScrollBy() async throws {
        let m = try await makeModel()
        let sections = m.sections(for: work)
        let shown = sections.filter { !$0.finished }.flatMap { $0.tasks.map(\.id) }
        #expect(pickedTasks(sections, [shown[2], shown[0]]).map(\.id) == [shown[0], shown[2]])
        #expect(pickedTasks(sections, []).isEmpty)
        let first = sections[0]
        // A folded group's picked tasks don't come along.
        let inFirst = try #require(first.tasks.first?.id)
        let elsewhere = try #require(sections[1].tasks.first?.id)
        #expect(pickedTasks(sections, [inFirst, elsewhere]) { $0.id == first.id }.map(\.id) == [elsewhere])
        #expect(shownRowIds(sections) { $0.id == first.id }.first == sections[1].tasks.first?.id)
    }
}

@Suite struct SelectAllAndSectionDialogs {
    @Test func commandAPicksEveryTaskOnTheBoardUnlessATextFieldHasTheKeyboard() async throws {
        let m = try await makeModel()
        m.settings.setLayout(work, .board)
        let order = m.boardOrder(work)
        #expect(order == BoardLayout.taskOrder(m.boardColumns(work)))
        // Typing in a column's field: ⌘A is the field's.
        m.selectAllTasks(order, textFocused: true)
        #expect(!m.selection.isActive)
        m.selectAllTasks(order, textFocused: false)
        #expect(m.selection.ids == Set(order))
        #expect(m.boardSelection.picking && order.allSatisfy(m.boardSelection.isSelected))
        #expect(SelectAllTarget.resolve(textFocused: true) == .text)
        #expect(SelectAllTarget.resolve(textFocused: false) == .tasks)
    }

    @Test func commandAPicksEveryTaskOnTheTimeline() async throws {
        let m = try await makeModel()
        m.settings.setLayout(work, .timeline)
        let order = m.timelineOrder(work)
        let t = m.timeline(for: work)
        #expect(Set(order) == Set(t.undatedTasks.map(\.id) + t.lanes.flatMap { $0.bars.map(\.task.id) }))
        #expect(!order.isEmpty)
        m.selectAllTasks(order, textFocused: false)
        #expect(m.selection.ids == Set(order))
        // Nothing shown: nothing picked.
        m.selection.clear()
        m.selectAllTasks([], textFocused: false)
        #expect(!m.selection.isActive)
    }

    @Test func theBoardsSectionDialogsAreTheAppsOwn() async throws {
        let m = try await makeModel()
        let actions = m.boardActions(work, order: m.boardOrder(work))
        let doing = m.sectionsByList["work"]!.first { $0.id == "work-doing" }!
        // Renaming from the column's ⋯ puts up DialogHost's text prompt and
        // nothing of the board's own.
        #expect(actions.route(.rename(doing)) == nil)
        let prompt = try #require(m.present.textPrompt)
        #expect(prompt.title == "重命名分组")
        prompt.onSubmit("本周")
        try await waitUntil { m.sectionsByList["work"]?.contains { $0.name == "本周" } == true }
        // Deleting asks with DialogHost's confirmation.
        #expect(actions.route(.delete(doing)) == nil)
        #expect(m.present.confirm != nil)
        #expect(actions.route(.add(listId: "work")) == nil)
        #expect(m.present.textPrompt?.title == "添加分组")
        // A board without the app's dialogs shows its own.
        #expect(BoardActions().route(.delete(doing)) == .delete(doing))
    }
}
