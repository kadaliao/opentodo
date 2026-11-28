// AppModel over a real (in-memory) database and TaskRepo, with the clock
// fixed at 2026-11-26 (a Thursday) 09:41 in Shanghai. The app_test.dart
// cases that can be said without a screen are here, named after them
// (`appTest…`); the rest cover what the model adds (routes, layouts,
// notes and undo, the sidebar's and the menus' actions).

import Foundation
import OpenTodoData
import OpenTodoDomain
import Testing
@testable import OpenTodoUI

nonisolated private let tz = TimeZone(identifier: "Asia/Shanghai")!
nonisolated private let now = LocalDateTime(2026, 11, 26, 9, 41)
nonisolated private let today = now.day

private func makeModel(demo: Bool = true, width: WidthClass = .regular) async throws -> AppModel {
    let db = try AppDatabase.inMemory()
    let settings = LocalSettings(db)
    let repo = TaskRepo(db, clock: { now.date(in: tz) }, defaults: settings.defaultsProvider, timeZone: tz)
    if demo { try await DemoData.seed(repo, now: now) }
    let model = AppModel(repo: repo, settings: settings, now: now)
    model.setWidth(width)
    await model.start(clock: false)
    try await waitUntil { model.loaded }
    return model
}

/// The observation delivers on the main queue after a write commits.
private func waitUntil(_ what: String = "", _ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("timed out \(what)")
}

private func settle(_ model: AppModel) async throws {
    let data = try await model.database.observeTaskData().first()
    try await waitUntil { model.data == data }
}

// MARK: - app_test.dart

@Suite struct AppTestCases {
    @Test func appTestAddATaskInTodayOpenItCompleteIt() async throws {
        let m = try await makeModel(demo: false)
        let empty = m.sections(for: .smart(.today)).allSatisfy { $0.tasks.isEmpty }
        #expect(empty) // 今天没有任务
        #expect(m.selectedTaskId == nil)                                      // 点击任务查看详情

        let preview = parseQuickAdd("下午3点开会 #工作", now: m.now)
        #expect(fullDueLabel(preview.date!, preview.time, today: today) == "今天, 下午3:00")
        let id = try #require(await m.quickAdd("下午3点开会 #工作"))
        try await settle(m)

        let t = try #require(m.task(id))
        #expect(t.title == "开会" && t.tags == ["工作"])
        #expect(m.selectedTaskId == id)                       // opens in the detail
        #expect(fullDueLabel(t.dueDate!, t.dueTime, today: today) == "今天, 下午3:00")
        #expect(m.tags == ["工作"])                           // the sidebar shows the tag
        #expect(m.count(of: .tag("工作")) == 1)
        #expect(m.notices.current == nil)                     // it shows in 今天: no note

        await m.setDone(t, true)
        try await settle(m)
        #expect(m.sections(for: .smart(.today)).last?.title == "已完成")
    }

    @Test func appTestDefaultRemindersFromTheSettings() async throws {
        let m = try await makeModel(demo: false)
        m.settings.setDefaults(TaskDefaults(timedReminders: [-30], allDayReminders: [540], spanMinutes: 30))
        let a = try #require(await m.quickAdd("明天交报告"))
        let b = try #require(await m.quickAdd("明天下午3点开会"))
        m.select(.smart(.inbox))
        let c = try #require(await m.quickAdd("读书"))
        try await settle(m)
        #expect(m.task(a)?.reminders == [540])
        #expect(m.task(b)?.reminders == [-30])
        #expect(m.task(c)?.reminders == [])                   // no date, none
        #expect(m.repo.database === m.settings.database)
        let stored = try m.database.getValueNow(Keys.settings)
        #expect(stored?.contains(#""allDayReminders":[540]"#) == true)
    }

    @Test func appTestPhoneSettingsAndNewTask() async throws {
        let m = try await makeModel(demo: false, width: .compact)
        m.apply(.settings(nil))
        #expect(m.present.settings)
        m.requestQuickAdd()
        #expect(m.present.quickAdd)
    }

    @Test func appTestPhoneTasksOpenAsAPage() async throws {
        let m = try await makeModel(demo: false, width: .compact)
        #expect(m.phonePath.isEmpty)                          // the views first
        m.select(.smart(.today))
        let id = try #require(await m.quickAdd("买菜"))
        try await settle(m)
        #expect(m.selectedTaskId == nil)                      // a phone doesn't open it
        m.open(taskId: id)
        #expect(m.phonePath == [.view(.smart(.today)), .task(id)])
    }

    @Test func appTestARepeatingTaskMovesOnWhenDoneWithUndo() async throws {
        let m = try await makeModel(demo: false)
        m.select(.smart(.tomorrow))
        let id = try #require(await m.quickAdd("明天上午9点每天吃药"))
        try await settle(m)
        var t = try #require(m.task(id))
        #expect(t.repeatRule == "FREQ=DAILY")
        #expect(t.reminders == [0])                           // a time comes with 准时

        await m.setDone(t, true)
        try await settle(m)
        #expect(m.notices.current?.text == "已完成，下次：后天")
        t = try #require(m.task(id))
        #expect(t.dueDate == today + 2 && t.status == .open)

        await m.notices.runAction()                           // 撤销
        try await settle(m)
        t = try #require(m.task(id))
        #expect(t.dueDate == today + 1)
        #expect(m.data.tasks.count == 1)
        #expect(m.notices.current == nil)
    }

    @Test func appTestOverdueTasksShowInRed() async throws {
        let m = try await makeModel(demo: false)
        try await m.repo.addTask(id: "midnight", title: "今天零点", dueDate: today, dueTime: 0, reminders: [0])
        try await m.repo.addTask(id: "yesterday", title: "昨天的", dueDate: today - 1)
        try await m.repo.addTask(id: "allday", title: "今天全天", dueDate: today)
        try await settle(m)
        let s = m.sections(for: .smart(.today))
        #expect(s.first?.title == "已过期" && s.first?.alert == true)
        let label = { (id: String) in DueLabel(m.task(id)!, now: m.now)! }
        #expect(label("midnight").overdue && label("midnight").text == "上午12:00" && label("midnight").reminds)
        #expect(label("yesterday").overdue && label("yesterday").text == "昨天")
        #expect(!label("allday").overdue && label("allday").text == "今天")
    }

    @Test func appTestTheDateDialogsResultIsApplied() async throws {
        let m = try await makeModel(demo: false)
        let id = try #require(await m.quickAdd("上午10点评审"))
        await m.setSchedule(id, ScheduleDraft(dueDate: today, dueTime: 600, duration: 60, reminders: [0]))
        try await settle(m)
        var t = try #require(m.task(id))
        #expect((t.dueTime, t.duration, t.reminders) == (600, 60, [0]))
        #expect(dueLabel(t.dueDate!, t.dueTime, today: today, duration: t.duration) == "上午10:00-11:00")
        await m.setSchedule(id, ScheduleDraft(dueDate: today, repeatRule: .weekly))
        try await settle(m)
        t = try #require(m.task(id))
        #expect(t.dueTime == nil && t.duration == nil && t.reminders.isEmpty && t.repeatRule == "FREQ=WEEKLY")
        await m.setSchedule(id, .cleared)
        try await settle(m)
        t = try #require(m.task(id))
        #expect(t.dueDate == nil && t.repeatRule == nil)
    }
}

// MARK: - The model

@Suite struct DemoDataTests {
    @Test func everyRecordPointsAtSomethingThatExists() async throws {
        let m = try await makeModel()
        let d = m.data
        let lists = Set(d.lists.map(\.id)).union([inboxListId])
        #expect(d.tasks.allSatisfy { lists.contains($0.listId) })
        let sections = Dictionary(uniqueKeysWithValues: d.sections.map { ($0.id, $0) })
        #expect(d.tasks.allSatisfy { t in t.sectionId.map { sections[$0]?.listId == t.listId } ?? true })
        let tasks = Set(d.tasks.map(\.id))
        #expect(d.checklistItems.allSatisfy { tasks.contains($0.taskId) })
    }

    @Test func hasEveryKindOfTaskTheScreensShow() async throws {
        let d = try await makeModel().data
        #expect(d.tasks.contains { isOverdue($0, now) })
        #expect(d.tasks.contains { $0.status == .done })
        #expect(d.tasks.contains { $0.repeatRule != nil })
        #expect(d.tasks.contains { $0.pinnedAt != nil })
        #expect(d.tasks.contains { $0.trashedAt != nil })
        #expect(d.tasks.contains { $0.duration != nil })
        #expect(d.tasks.contains { !$0.reminders.isEmpty })
        #expect(d.tasks.contains { $0.dueDate != nil && $0.dueTime == nil })
        #expect(d.tasks.contains { $0.dueDate == nil })
        #expect(Set(d.tasks.map(\.priority)) == Set(Priority.allCases))
        #expect(!d.filters.isEmpty)
    }

    @Test func seedsOnlyAnEmptyDatabase() async throws {
        let m = try await makeModel()
        let before = m.data.tasks.count
        try await DemoData.seed(m.repo, now: now)
        #expect(try await m.database.observeTasks().first().count == before)
    }
}

@Suite struct AppModelTests {
    @Test func startsOnTodayWithNothingOpen() async throws {
        let m = try await makeModel()
        #expect(m.module == .tasks && m.view == .smart(.today) && m.selectedTaskId == nil)
    }

    @Test func countsOpenTasksPerView() async throws {
        let m = try await makeModel()
        // 评审 / 报销 (overdue) + 改版上线 (a span over today) / 浇水 / 周会 / 总结 / 超市 (today).
        #expect(m.count(of: .smart(.today)) == 7)
        #expect(m.count(of: .smart(.inbox)) == 3)
        #expect(m.count(of: .list("work")) == 9)
        #expect(m.count(of: .filter("important-week")) >= 1)
    }

    @Test func listsTagsOnlyFromTasksOutsideTheTrash() async throws {
        let m = try await makeModel()
        #expect(m.tags == ["出行", "家", "工作", "想法", "读书", "财务"].sorted())
        try await m.repo.setTags("old", ["垃圾"])
        try await settle(m)
        #expect(!m.tags.contains("垃圾"))
    }

    @Test func todayShowsOverdueTodayAndDone() async throws {
        let m = try await makeModel()
        let s = m.sections(for: .smart(.today))
        #expect(s.map(\.title) == ["已过期", daySectionTitle(today, today: today), "已完成"])
        #expect(s[0].tasks.map(\.id).sorted() == ["invoice", "review"])
        #expect(s[1].tasks.map(\.id) == ["launch", "plants", "standup", "report", "milk"])
    }

    @Test func next7ShowsEveryDayEvenEmptyOnes() async throws {
        let m = try await makeModel()
        let days = m.sections(for: .smart(.next7)).compactMap(\.day)
        #expect(days == (0..<7).map { today + $0 })
    }

    @Test func groupingSortAndLayoutAreKeptPerView() async throws {
        let m = try await makeModel()
        #expect(m.sections(for: .list("work")).map(\.title) == ["进行中", "待安排", "已完成"])
        m.settings.setGrouping(.list("work"), .priority)
        #expect(m.sections(for: .list("work")).first?.title == "高优先级")
        m.settings.setSort(.list("work"), .title)
        m.settings.setLayout(.list("work"), .board)
        #expect(m.prefs(for: .list("work")).layoutIn(.list("work")) == .board)
        #expect(m.prefs(for: .smart(.today)).layoutIn(.smart(.today)) == .list)
        // Kept in key_values, so a new window reads them back.
        #expect(LocalSettings(m.database).viewPrefs(for: .list("work")).grouping == .priority)
        #expect(layouts(for: .list("work")) == [.list, .board, .timeline])
        #expect(layouts(for: .smart(.today)) == [.list, .timeline])
        #expect(layouts(for: .smart(.trash)) == [.list])
    }

    @Test func doneCanBeHiddenPerView() async throws {
        let m = try await makeModel()
        m.taskList.setShowsDone(false, .smart(.today))
        #expect(!m.sections(for: .smart(.today)).contains { $0.title == "已完成" })
        #expect(m.sections(for: .list("fitness")).contains { $0.title == "已完成" })
    }

    @Test func groupsFoldPerView() async throws {
        let m = try await makeModel()
        let done = m.sections(for: .list("work")).last!
        #expect(m.taskList.isFolded(done, in: .list("work")))         // a list's 已完成 starts folded
        m.taskList.setFolded(false, done, in: .list("work"))
        #expect(!m.taskList.isFolded(done, in: .list("work")))
        let todayDone = m.sections(for: .smart(.today)).last!
        #expect(!m.taskList.isFolded(todayDone, in: .smart(.today)))
    }

    @Test func changingViewsClosesTheTask() async throws {
        let m = try await makeModel()
        m.open(taskId: "report")
        m.select(.list("work"))
        #expect(m.selectedTaskId == nil)
    }

    @Test func theMacSidebarSelectsViewsAndModules() async throws {
        let m = try await makeModel()
        #expect(m.sidebarSelection == .view(.smart(.today)))
        #expect(AppModule.sidebarModules == [.calendar, .matrix, .focus, .habits, .countdowns])

        // A module's row: the module shows, the view is kept for coming back.
        m.choose(.view(.list("work")))
        m.open(taskId: "report")
        m.choose(.module(.calendar))
        #expect(m.module == .calendar && m.sidebarSelection == .module(.calendar))
        #expect(m.view == .list("work") && m.selectedTaskId == nil)       // changing module closes the task

        // From one module straight to another.
        m.choose(.module(.habits))
        #expect(m.module == .habits && m.sidebarSelection == .module(.habits))

        // A view's row from another module: back in the tasks module, on that view.
        m.choose(.view(.smart(.inbox)))
        #expect(m.module == .tasks && m.view == .smart(.inbox) && m.sidebarSelection == .view(.smart(.inbox)))

        // ⌘1 from another module comes back to the view last shown.
        m.choose(.module(.focus))
        m.switchTo(.tasks)
        #expect(m.sidebarSelection == .view(.smart(.inbox)))
    }

    #if os(macOS)
    @Test func theDetailGivesWayToTheListInANarrowWindow() {
        // The default window (1180) less the sidebar: the detail as chosen.
        #expect(TaskSplitLogic.detailWidth(wanted: 380, total: 942) == 380)
        // Dragged past the limits.
        #expect(TaskSplitLogic.detailWidth(wanted: 100, total: 942) == TaskSplitLogic.minDetailWidth)
        #expect(TaskSplitLogic.detailWidth(wanted: 900, total: 1400) == TaskSplitLogic.maxDetailWidth)
        // Dragged wide in a window that can't give it: the list keeps its minimum.
        #expect(TaskSplitLogic.detailWidth(wanted: 560, total: 700) == 700 - TaskSplitLogic.minListWidth - TaskSplitLogic.handleWidth)
        // The smallest window (760) beside a sidebar of 230: both fit.
        let narrow = TaskSplitLogic.detailWidth(wanted: 380, total: 522)
        #expect(narrow == 233 && narrow + TaskSplitLogic.minListWidth + TaskSplitLogic.handleWidth <= 522)
        // … and beside the widest sidebar (320) the detail stops at its least.
        #expect(TaskSplitLogic.detailWidth(wanted: 380, total: 432) == TaskSplitLogic.leastDetailWidth)
    }
    #endif

    @Test func routesOpenViewsTasksAndModules() async throws {
        let m = try await makeModel()
        m.apply(DebugRoute("list:work")!)
        #expect(m.view == .list("work"))
        m.apply(DebugRoute("list:inbox")!)
        #expect(m.view == .smart(.inbox))
        m.apply(DebugRoute("tag:工作")!)
        #expect(m.view == .tag("工作"))
        m.apply(DebugRoute("task:report")!)                   // in the current view
        #expect(m.view == .tag("工作") && m.selectedTaskId == "report")
        m.apply(DebugRoute("task:battery")!)                  // else where it belongs
        #expect(m.view == .list("shopping") && m.selectedTaskId == "battery")
        m.apply(DebugRoute("task:old")!)
        #expect(m.view == .smart(.trash))
        m.apply(DebugRoute("calendar:month")!)
        #expect(m.module == .calendar)
        m.revealTask("milk")
        #expect(m.module == .tasks && m.selectedTaskId == "milk")
        m.apply(DebugRoute("smart:someday")!)
        #expect(m.view == .smart(.today))
    }

    @Test func aRouteWaitsForTheData() async throws {
        let db = try AppDatabase.inMemory()
        let repo = TaskRepo(db, clock: { now.date(in: tz) }, timeZone: tz)
        let m = AppModel(repo: repo, now: now) { try? await DemoData.seed(repo, now: now) }
        m.applyWhenLoaded(.task("slides"))
        #expect(m.selectedTaskId == nil)
        await m.start(clock: false)
        try await waitUntil { m.selectedTaskId == "slides" }
        #expect(m.view == .smart(.next7) || m.view == .list("work"))
    }

    @Test func launchSeedsTheWelcomeListOnAFreshDatabase() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ot-launch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let m = AppModel.forLaunch(DebugLaunch(databasePath: dir.appending(path: "a.sqlite").path))
        await m.start(clock: false)
        try await waitUntil { m.lists.contains { $0.id == TaskRepo.seedListId } }
        let demo = AppModel.forLaunch(DebugLaunch(databasePath: dir.appending(path: "b.sqlite").path, seed: .demo,
                                                  open: .list("work")))
        await demo.start(clock: false)
        try await waitUntil { demo.listsById["work"] != nil }
        #expect(demo.view == .list("work"))
        #expect(!demo.lists.contains { $0.id == TaskRepo.seedListId })
    }

    @Test func aPhoneStartsAtTheViewsUnlessARouteOpenedOne() async throws {
        let home = try await makeModel(width: .compact)
        #expect(home.phonePath.isEmpty)
        let m = try await makeModel()
        m.apply(.task("report"))
        m.setWidth(.compact)
        #expect(m.phonePath == [.view(.smart(.today)), .task("report")])
        m.phonePath.removeLast()
        m.phonePathChanged()
        #expect(m.selectedTaskId == nil && m.view == .smart(.today))
        m.setWidth(.regular)
        m.open(taskId: "milk")
        m.setWidth(.compact)
        #expect(m.phonePath == [.view(.smart(.today)), .task("milk")])
    }

    @Test func inTheTrashSelectAllPicksAndOpensNothing() async throws {
        let m = try await makeModel()
        try await m.repo.trashTask("report")
        try await m.repo.trashTask("milk")
        try await settle(m)
        m.select(.smart(.trash))
        let rows = m.listSelection(in: .smart(.trash))
        rows.wrappedValue = ["report", "milk"] // ⌘A
        #expect(m.selectedTaskId == nil && !m.selection.isActive)
        rows.wrappedValue = ["milk"] // a click opens it
        #expect(m.selectedTaskId == "milk" && !m.selection.isActive)
    }

    @Test func aPhoneOpeningAnotherViewStopsPicking() async throws {
        let m = try await makeModel(width: .compact)
        m.select(.list("work"))
        m.selection.start("report")
        #expect(m.selection.isPicking)
        m.phonePath = []
        m.phonePathChanged()
        m.phonePath = [.view(.list("life"))]
        m.phonePathChanged()
        #expect(m.view == .list("life") && !m.selection.isPicking && !m.selection.isActive)
    }

    @Test func quickAddTakesTheViewsDefaultsAndSaysWhereItWent() async throws {
        let m = try await makeModel()
        m.select(.list("reading"))
        let a = try #require(await m.quickAdd("  读《长安的荔枝》 "))
        #expect(m.notices.current == nil)
        m.select(.smart(.today))
        let b = try #require(await m.quickAdd("下周三取干洗的衣服"))
        #expect(m.notices.current?.text.hasPrefix("已添加到") == true)
        m.select(.tag("家"))
        let c = try #require(await m.quickAdd("修水龙头 #工具 !高"))
        m.select(.filter("important-week"))
        _ = try #require(await m.quickAdd("随便记一下"))
        #expect(m.notices.current?.text.contains("不符合这个过滤器的条件") == true)
        let target = try #require(await m.quickAdd("写大纲", target: QuickAddTarget(listId: "work", sectionId: "work-later")))
        #expect(await m.quickAdd("   ") == nil)
        try await settle(m)
        #expect(m.task(a)?.title == "读《长安的荔枝》" && m.task(a)?.listId == "reading")
        #expect(m.task(b)?.dueDate != nil && m.task(b)?.listId == inboxListId)
        #expect(m.task(c)?.tags == ["家", "工具"] && m.task(c)?.priority == .high)
        #expect(m.task(target)?.sectionId == "work-later")
        #expect(m.selectedTaskId != target)                   // a target's task isn't opened
    }

    @Test func trashingHasAnUndoAndClosesTheTask() async throws {
        let m = try await makeModel()
        m.open(taskId: "milk")
        await m.trash(m.task("milk")!)
        try await settle(m)
        #expect(m.task("milk")?.trashedAt != nil && m.selectedTaskId == nil)
        #expect(m.notices.current?.text == "已删除“超市：牛奶、鸡蛋、面包”")
        await m.notices.runAction()
        try await settle(m)
        #expect(m.task("milk")?.trashedAt == nil)
    }

    @Test func trashRestorePurgeAndEmpty() async throws {
        let m = try await makeModel()
        await m.restore(m.task("old")!)
        try await settle(m)
        #expect(m.task("old")?.trashedAt == nil)
        await m.trash(m.task("old")!)
        await m.trash(m.task("battery")!)
        try await settle(m)
        await m.purge(m.task("old")!)
        try await settle(m)
        #expect(m.task("old") == nil)
        m.askEmptyTrash()
        let ask = try #require(m.present.confirm)
        #expect(ask.title == "清空垃圾桶？" && ask.destructive)
        ask.onConfirm()
        try await waitUntil { m.sections(for: .smart(.trash)).isEmpty }
    }

    @Test func menuDateShortcutsKeepTheTime() async throws {
        let m = try await makeModel()
        await m.setQuickDate(m.task("invoice")!, .today)
        await m.setQuickDate(m.task("okr")!, .tomorrow)
        await m.setQuickDate(m.task("battery")!, .nextWeek)
        await m.setQuickDate(m.task("gift")!, .none)
        try await settle(m)
        #expect(m.task("invoice")?.dueDate == today && m.task("invoice")?.dueTime == 18 * 60)
        #expect(m.task("okr")?.dueDate == today + 1)
        #expect(m.task("battery")?.dueDate == Day(2026, 11, 30))   // 下周一
        #expect(m.task("gift")?.dueDate == nil)
    }

    @Test func skippingARepeatSaysWhenNext() async throws {
        let m = try await makeModel()
        await m.skip(m.task("plants")!)
        try await settle(m)
        #expect(m.task("plants")?.dueDate == today + 3)
        #expect(m.notices.current?.text == "已跳过，下次：\(dateLabel(today + 3, today: today))")
    }

    @Test func tagsPriorityListAndPin() async throws {
        let m = try await makeModel()
        await m.toggleTag(m.task("okr")!, "工作")
        try await settle(m)
        #expect(m.task("okr")?.tags == ["工作"])
        await m.toggleTag(m.task("okr")!, "工作")
        try await settle(m)
        m.askNewTag(m.task("okr")!)
        m.present.textPrompt?.onSubmit(" #计划 ")
        try await waitUntil { m.task("okr")?.tags == ["计划"] }
        try await m.repo.setPriority("okr", .high)
        try await m.repo.moveToList("okr", "life")
        try await m.repo.setPinned("okr", true)
        try await settle(m)
        let t = m.task("okr")!
        #expect(t.priority == .high && t.listId == "life" && t.pinnedAt != nil)
    }

    @Test func duplicateCopiesNotesAndSubtasks() async throws {
        let m = try await makeModel()
        let id = try #require(await m.duplicate(m.task("report")!))
        try await settle(m)
        let copy = try #require(m.task(id))
        #expect(copy.title == "写第四季度工作总结" && copy.content.hasPrefix("重点写") && copy.tags == ["工作"])
        #expect(m.checklist(of: id).map(\.title) == m.checklist(of: "report").map(\.title))
        #expect(m.checklistProgress(of: id).done == 2)
        #expect(m.selectedTaskId == id)
    }

    @Test func listsAddEditDeleteAndReorder() async throws {
        let m = try await makeModel()
        await m.addList(name: "旅行", emoji: "✈️")
        try await settle(m)
        let trip = try #require(m.lists.first { $0.name == "旅行" })
        #expect(m.view == .list(trip.id))
        await m.moveList(trip.id, to: 0)
        try await settle(m)
        #expect(m.lists.first?.id == trip.id)
        m.select(.list("shopping"))
        m.askDeleteList(m.listsById["shopping"]!)
        #expect(m.present.confirm?.title == "删除清单“购物”？")
        m.present.confirm?.onConfirm()
        try await waitUntil { m.listsById["shopping"] == nil }
        #expect(m.view == .smart(.inbox))
        #expect(m.task("milk")?.trashedAt != nil)
    }

    @Test func filtersAskTheEditorAndConfirmDeleting() async throws {
        let m = try await makeModel()
        m.editFilter()
        #expect(m.present.filterEditor?.filter == nil)
        m.select(.filter("important-week"))
        m.askDeleteFilter(m.filtersById["important-week"]!)
        #expect(m.present.confirm?.message == "只删除过滤器，里面的任务不受影响。")
        m.present.confirm?.onConfirm()
        try await waitUntil { m.filters.isEmpty }
        #expect(m.view == .smart(.today))
    }

    @Test func sectionsAddRenameMoveDelete() async throws {
        let m = try await makeModel()
        m.settings.setGrouping(.list("life"), .none)
        m.askAddSection("life")
        m.present.textPrompt?.onSubmit("本周")
        try await waitUntil { m.sectionsByList["life"]?.count == 1 }
        #expect(m.prefs(for: .list("life")).groupingIn(.list("life")) == .sections)
        let doing = m.sectionsByList["work"]![0]
        await m.moveSection(doing, by: 1)
        try await settle(m)
        #expect(m.sectionsByList["work"]!.map(\.id) == ["work-later", "work-doing"])
        m.askRenameSection(doing)
        m.present.textPrompt?.onSubmit("正在做")
        try await waitUntil { m.sectionsByList["work"]!.contains { $0.name == "正在做" } }
        m.askDeleteSection(m.sectionsByList["work"]![0])
        m.present.confirm?.onConfirm()
        try await waitUntil { m.sectionsByList["work"]?.count == 1 }
        #expect(m.task("okr")?.listId == "work")
    }

    @Test func checklistReorders() async throws {
        let m = try await makeModel()
        let items = m.checklist(of: "report")
        await m.moveChecklistItem(items[4], to: 0)
        try await settle(m)
        #expect(m.checklist(of: "report").first?.title == "请同事看一遍")
    }

    @Test func aDeletedSelectedTaskIsDeselected() async throws {
        let m = try await makeModel()
        m.open(taskId: "report")
        try await m.repo.purgeTask("report")
        try await settle(m)
        #expect(m.selectedTaskId == nil)
    }

    @Test func newTaskGoesToTheFieldOrTheSheet() async throws {
        let wide = try await makeModel()
        wide.switchTo(.calendar)
        wide.requestQuickAdd()
        #expect(wide.module == .tasks && wide.taskList.quickAddRequests == 1 && !wide.present.quickAdd)
        // A board has no field at the top: ⌘N opens the sheet instead.
        wide.select(.list("work"))
        wide.settings.setLayout(.list("work"), .board)
        wide.requestQuickAdd()
        #expect(wide.present.quickAdd && wide.taskList.quickAddRequests == 1)
    }

    @Test func notesCanBeDismissedAndRunOnce() async throws {
        let n = Notices()
        var runs = 0
        n.show("已删除", undo: { runs += 1 })
        await n.runAction()
        await n.runAction()
        #expect(runs == 1 && n.current == nil)
        n.show("已添加到明天")
        #expect(n.current?.action == nil)
    }
}

@Suite struct ModuleTests {
    @Test func shortcutsFollowTheOrder() {
        #expect(AppModule.allCases.map { String($0.shortcut.character) } == ["1", "2", "3", "4", "5", "6"])
    }
}

@Suite struct SelectionModelTests {
    @Test func tapsPickWithModifiersAndOpenWithout() {
        let s = SelectionModel()
        let order = ["a", "b", "c", "d"]
        #expect(s.tap("b", order: order, current: nil, touch: false) == "b")   // a plain click opens
        #expect(s.tap("c", modifiers: .command, order: order, current: "b", touch: false) == nil)
        #expect(s.ids == ["b", "c"] && s.anchor == "c")                       // ⌘ takes the open one along
        s.tap("a", modifiers: .shift, order: order, current: "b", touch: false)
        #expect(s.ids.isSuperset(of: ["a", "b", "c"]))
        #expect(s.tap("d", order: order, current: "b", touch: false) == "d")   // plain click: stop picking
        #expect(!s.isActive)
        s.selectAll(order)
        #expect(s.ids == Set(order))
        s.clear()
        #expect(!s.isActive && !s.isPicking)
    }

    @Test func iOSPickingModeTogglesOnTap() {
        let s = SelectionModel()
        s.isPicking = true
        #expect(s.tap("a", order: ["a"], current: nil, touch: false) == nil)
        #expect(s.contains("a"))
        s.start("b")
        #expect(s.ids == ["b"] && s.isPicking)
    }

    @Test func changingViewOrModuleClearsIt() async throws {
        let m = try await makeModel()
        m.selection.start("report")
        m.select(.list("work"))
        #expect(!m.selection.isActive)
        m.selection.start("okr")
        m.switchTo(.calendar)
        #expect(!m.selection.isActive)
    }
}

// MARK: - Multi-select and batch actions (selection_test.dart, batch_actions.dart)

@Suite struct BatchTests {
    @Test func shownOrderSkipsFoldedGroups() async throws {
        let m = try await makeModel()
        let all = m.shownOrder(in: .list("work"))
        #expect(!all.contains("email"))                               // 已完成 is folded in a list
        let later = m.sections(for: .list("work")).first { $0.title == "待安排" }!
        m.taskList.setFolded(true, later, in: .list("work"))
        #expect(!m.shownOrder(in: .list("work")).contains("okr"))
        #expect(m.shownOrder(in: .list("work")).first == "slides")    // pinned first
    }

    @Test func theListSelectionOpensOneAndPicksSeveral() async throws {
        let m = try await makeModel()
        m.select(.list("work"))
        let sel = m.listSelection(in: .list("work"))
        sel.wrappedValue = ["report"]
        #expect(m.selectedTaskId == "report" && !m.selection.isActive)
        sel.wrappedValue = ["report", "okr"]                          // ⌘-click: the open one comes along
        #expect(m.selection.ids == ["report", "okr"])
        #expect(m.batchSelection?.count == 2)
        #expect(sel.wrappedValue == ["report", "okr"])                // the rows show the picked ones
        sel.wrappedValue = ["okr"]                                    // a plain click
        #expect(!m.selection.isActive && m.selectedTaskId == "okr")
    }

    @Test func nothingIsPickedInTheTrash() async throws {
        let m = try await makeModel()
        m.select(.smart(.trash))
        #expect(!m.canPick(in: .smart(.trash)))
        try await m.repo.trashTask("milk")
        try await settle(m)
        m.listSelection(in: .smart(.trash)).wrappedValue = ["old", "milk"] // ⌘A: nothing, as in Flutter
        #expect(!m.selection.isActive && m.selectedTaskId == nil)
        m.listSelection(in: .smart(.trash)).wrappedValue = ["milk"]        // a click opens
        #expect(!m.selection.isActive && m.selectedTaskId == "milk")
    }

    @Test func phonePickingModeTapsPick() async throws {
        let m = try await makeModel(width: .compact)
        m.select(.list("work"))
        m.selection.start("report")
        let sel = m.listSelection(in: .list("work"))
        sel.wrappedValue = ["report", "okr"]
        sel.wrappedValue = ["okr"]                                    // still picking, one left
        #expect(m.selection.isPicking && m.selection.ids == ["okr"])
        #expect(m.phonePath == [.view(.list("work"))])                // nothing opened
    }

    @Test func batchChangesKeepEachTasksTime() async throws {
        let m = try await makeModel()
        m.select(.list("work"))
        m.selection.replace(with: ["report", "invoice", "okr"])
        let b = try #require(m.batchSelection)
        await m.performBatch(b.setDue(today + 1))
        await m.performBatch(b.setPriority(.low))
        await m.performBatch(b.move(to: "life"))
        await m.performBatch(b.togglePin)
        var tags = BatchTagsEditor(tasks: b.tasks, known: m.tags)
        tags.toggle("财务")                                            // some have it: tick adds to all
        await m.performBatch(tags.action)
        try await settle(m)
        for id in ["report", "invoice", "okr"] {
            let t = m.task(id)!
            #expect(t.dueDate == today + 1 && t.priority == .low && t.listId == "life" && t.pinnedAt != nil)
            #expect(t.tags.contains("财务"))
        }
        #expect(m.task("report")?.dueTime == 15 * 60 && m.task("invoice")?.dueTime == 18 * 60)
        #expect(m.selection.ids.count == 3)                           // still picked
    }

    @Test func completingClearsTheSelectionAndUndoes() async throws {
        let m = try await makeModel()
        m.selection.replace(with: ["report", "plants"])               // plants repeats
        await m.performBatch(m.batchSelection!.complete)
        try await settle(m)
        #expect(!m.selection.isActive && m.notices.current?.text == "已完成 2 个任务")
        #expect(m.task("report")?.status == .done && m.task("plants")?.dueDate == today + 3)
        await m.notices.runAction()
        try await settle(m)
        #expect(m.task("report")?.status == .open && m.task("plants")?.dueDate == today)
    }

    @Test func trashingClearsTheSelectionAndUndoes() async throws {
        let m = try await makeModel()
        m.open(taskId: "milk")
        m.selection.replace(with: ["milk", "battery"])
        await m.performBatch(m.batchSelection!.trash)
        try await settle(m)
        #expect(m.notices.current?.text == "已把 2 个任务移到垃圾桶")
        #expect(!m.selection.isActive && m.selectedTaskId == nil)
        await m.notices.runAction()
        try await settle(m)
        #expect(m.task("milk")?.trashedAt == nil && m.task("battery")?.trashedAt == nil)
    }

    @Test func selectAllClearAndCopiedTitles() async throws {
        let m = try await makeModel()
        m.select(.list("work"))
        m.selection.start("okr")
        await m.performBatch(.selectAll)
        #expect(m.selection.ids == Set(m.shownOrder(in: .list("work"))))
        await m.performBatch(.copiedTitles(count: 3))
        #expect(m.notices.current?.text == "已复制 3 个任务的标题")
        await m.performBatch(.clearSelection)
        #expect(!m.selection.isActive)
    }
}

@Suite struct ServicesTests {
    @Test func aWindowRunsOnTheAppsServices() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ot-services-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let debug = DebugLaunch(databasePath: dir.appending(path: "a.sqlite").path, seed: .demo)
        let services = AppModel.launchServices(debug)
        let a = AppModel.forLaunch(debug, services: services)
        let b = AppModel.forLaunch(debug, services: services)
        #expect(a.repo === services.repo && b.settings === services.settings)
        await a.start(clock: false)
        await b.start(clock: false)
        try await waitUntil { a.task("report") != nil && b.task("report") != nil }
        #expect(a.data.tasks.count == b.data.tasks.count)            // seeded once
        a.handle(.task("battery"))                                    // opened from a notification
        #expect(a.view == .list("shopping") && a.selectedTaskId == "battery")
    }
}

@Suite struct ModuleSwitchTests {
    @Test func switchingModulesClosesTheTaskOnAWideWindowOnly() async throws {
        let wide = try await makeModel()
        wide.open(taskId: "report")
        wide.switchTo(.calendar)
        #expect(wide.selectedTaskId == nil)
        wide.revealTask("milk")                                       // back to tasks, opened
        #expect(wide.module == .tasks && wide.selectedTaskId == "milk")

        let phone = try await makeModel(width: .compact)
        phone.select(.list("work"))
        phone.open(taskId: "okr")
        phone.switchTo(.habits)
        phone.switchTo(.tasks)
        #expect(phone.selectedTaskId == "okr" && phone.phonePath.last == .task("okr"))
    }
}

// MARK: - Sorting by hand where the view sorted by time

@Suite struct SortByHandTests {
    @Test func todaySwitchesToManualKeepingTheOrderShown() async throws {
        let m = try await makeModel()
        let view = ViewRef.smart(.today)
        #expect(m.prefs(for: view).sortIn(view) == .due)
        let before = m.sections(for: view).filter { !$0.finished }.map { $0.tasks.map(\.id) }
        await m.sortByHand(view)
        try await settle(m)
        #expect(m.prefs(for: view).sortIn(view) == .manual)
        let after = m.sections(for: view).filter { !$0.finished }.map { $0.tasks.map(\.id) }
        #expect(after == before)
        // Then a drag within a day writes the new place.
        let day = try #require(m.sections(for: view).first { !$0.finished && $0.target != nil && $0.tasks.count > 1 })
        let group = try #require(GroupDrop(day))
        #expect(group.manual)
        let last = try #require(day.tasks.last)
        let plan = try #require(group.plan(DraggedTasks(last), at: 0))
        await m.dropTasks(plan)
        try await settle(m)
        let moved = try #require(m.sections(for: view).first { $0.id == day.id })
        // First among the unpinned (pinned ones stay on top).
        let firstUnpinned = moved.tasks.first { $0.pinnedAt == nil }
        #expect(last.pinnedAt != nil || firstUnpinned?.id == last.id)
    }
}
