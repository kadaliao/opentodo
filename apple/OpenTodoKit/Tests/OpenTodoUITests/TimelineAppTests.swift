// The timeline in the app, on AppModel over a real (in-memory) database:
// what each view's timeline shows and what the edits from the component
// write. The behaviour checked by `app/test/timeline_ui_test.dart`, case by
// case where it can be said without a screen (the drags themselves are the
// component's; from a pointer to an edit is in TimelineLayoutTests).

import Foundation
import OpenTodoData
import OpenTodoDomain
import Testing
@testable import OpenTodoUI

nonisolated private let tz = TimeZone(identifier: "Asia/Shanghai")!
nonisolated private let now = LocalDateTime(2026, 11, 15, 10) // Sunday
nonisolated private let today = now.day

private func makeModel() async throws -> AppModel {
    let db = try AppDatabase.inMemory()
    let settings = LocalSettings(db)
    let repo = TaskRepo(db, clock: { now.date(in: tz) }, defaults: settings.defaultsProvider, timeZone: tz)
    let model = AppModel(repo: repo, settings: settings, now: now)
    await model.start(clock: false)
    try await waitUntil { model.loaded }
    return model
}

private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("timed out")
}

/// Waits for the latest write to come back through the observation.
private func settle(_ model: AppModel) async throws {
    let data = try await model.database.observeTaskData().first()
    try await waitUntil { model.data == data }
}

private func lanes(_ t: Timeline) -> [String] {
    t.lanes.map { "\($0.title ?? "null"): \($0.bars.map(\.task.title).joined(separator: ", "))" }
}

/// What letting go of `ids` (led by the first) on a lane standing for
/// `target`, with the lead starting on `start`, writes.
private func drop(_ m: AppModel, _ ids: [String], on start: Day, into target: GroupTarget?) throws -> TimelineEdit {
    let tasks = ids.compactMap(m.task)
    let lead = try #require(tasks.first)
    let days = lead.dueDate == nil ? 1 : TimelineBar(lead).days
    let p = try #require(TimelineDragMath.placement(
        dragged: tasks, lead: lead, drop: TimelineDropDays(start: start, days: days), target: target))
    return .place(p)
}

@Suite("timeline in the app")
struct TimelineAppTests {
    @Test("move tasks along the days, onto the timeline and off it, stretch them")
    func moveAndStretch() async throws {
        let m = try await makeModel()
        let work = try await m.repo.addList("工作")
        let jia = try await m.repo.addTask(title: "甲", listId: work, dueDate: today)
        let yi = try await m.repo.addTask(title: "乙", listId: work, dueDate: today, dueTime: 9 * 60)
        let bing = try await m.repo.addTask(title: "丙", listId: work)
        try await settle(m)
        m.select(.list(work))
        m.settings.setLayout(.list(work), .timeline)
        #expect(m.prefs(for: .list(work)).layoutIn(.list(work)) == .timeline)
        #expect(m.timeline(for: .list(work)).undatedTasks.map(\.title) == ["丙"])

        // 甲 two days on.
        await m.applyTimelineEdit(.place(TimelinePlacement(ids: [jia], days: 2, day: today + 2, target: nil)))
        // 乙 a day back, keeping its time.
        await m.applyTimelineEdit(.place(TimelinePlacement(ids: [yi], days: -1, day: today - 1, target: nil)))
        // 丙 from 无日期 onto 甲's day.
        await m.applyTimelineEdit(.place(TimelinePlacement(ids: [bing], days: 0, day: today + 2, target: nil)))
        try await settle(m)
        #expect(m.task(jia)?.dueDate == today + 2)
        #expect(m.task(yi)?.dueDate == today - 1 && m.task(yi)?.dueTime == 9 * 60)
        #expect(m.task(bing)?.dueDate == today + 2 && m.task(bing)?.dueTime == nil)
        #expect(m.timeline(for: .list(work)).undatedTasks.isEmpty)

        // 甲 back to 无日期.
        await m.applyTimelineEdit(.unschedule([jia]))
        try await settle(m)
        #expect(m.task(jia)?.dueDate == nil)

        // 乙's right edge two days on: 9:00 to 9:00 two days later.
        let y = try #require(m.task(yi))
        let stretch = try #require(TimelineDragMath.resizeEdit(y, start: false, day: today + 1))
        await m.applyTimelineEdit(stretch)
        try await settle(m)
        #expect(m.task(yi)?.duration == 2 * minutesPerDay)
        // Its left edge a day on: it starts a day later and still ends there.
        let y2 = try #require(m.task(yi))
        let later = try #require(TimelineDragMath.resizeEdit(y2, start: true, day: today))
        await m.applyTimelineEdit(later)
        try await settle(m)
        #expect(m.task(yi)?.dueDate == today && m.task(yi)?.duration == minutesPerDay && m.task(yi)?.dueTime == 9 * 60)
    }

    @Test("今天 and a tag as a timeline, with lanes by list")
    func todayAndTag() async throws {
        let m = try await makeModel()
        let work = try await m.repo.addList("工作")
        let rent = try await m.repo.addTask(title: "交房租", dueDate: today - 1)
        _ = try await m.repo.addTask(title: "晨会", listId: work, dueDate: today, tags: ["会"])
        let idea = try await m.repo.addTask(title: "想法", listId: work, tags: ["会"])
        try await settle(m)

        // A lane per list; nothing undated in 今天.
        let t = m.timeline(for: .smart(.today))
        #expect(lanes(t) == ["收集箱: 交房租", "工作: 晨会"])
        #expect(!t.takesUndated)

        // 交房租 down into 工作's lane: it moves to that list, on the same day.
        let lane = t.lanes[1].target
        await m.applyTimelineEdit(try drop(m, [rent], on: today - 1, into: lane))
        try await settle(m)
        #expect(m.task(rent)?.listId == work && m.task(rent)?.dueDate == today - 1)

        // A click on tomorrow adds nothing (今天 wouldn't show it); on today
        // it adds to the lane's list.
        #expect(!dateViewShows(.smart(.today), today + 1, today))
        let target = m.timelineNewTask(in: .smart(.today), on: today, lane: lane)
        #expect(target == QuickAddTarget(listId: work, date: today))
        let added = try #require(await m.quickAdd("写日报", target: target))
        try await settle(m)
        #expect(m.task(added)?.listId == work && m.task(added)?.dueDate == today)

        // Lanes by list, tag, priority or none; not by date.
        #expect(timelineGroupingsFor(.smart(.today)) == [.list, .tag, .priority, .none])
        m.settings.setGrouping(.smart(.today), .none)
        #expect(lanes(m.timeline(for: .smart(.today))).count == 1)

        // A tag: its undated task waits beside, and dragged on keeps its list
        // and tag.
        let tag = m.timeline(for: .tag("会"))
        #expect(tag.undatedTasks.map(\.title) == ["想法"])
        await m.applyTimelineEdit(try drop(m, [idea], on: today + 3, into: tag.lanes[0].target))
        try await settle(m)
        #expect(m.task(idea)?.dueDate == today + 3 && m.task(idea)?.listId == work && m.task(idea)?.tags == ["会"])
    }

    @Test("lanes for sections, a click adds to the section, picked tasks move together, options kept")
    func sectionsAndPicking() async throws {
        let m = try await makeModel()
        let work = try await m.repo.addList("工作")
        let design = try await m.repo.addSection(work, "设计")
        let dev = try await m.repo.addSection(work, "开发")
        let jia = try await m.repo.addTask(title: "甲", listId: work, sectionId: design, dueDate: today)
        let yi = try await m.repo.addTask(title: "乙", listId: work, sectionId: design, dueDate: today + 1)
        _ = try await m.repo.addTask(title: "开发", listId: work, sectionId: dev)
        try await settle(m)
        m.select(.list(work))

        // A lane per section; 未分组 has nothing dated, so isn't one.
        let t = m.timeline(for: .list(work))
        #expect(lanes(t) == ["设计: 甲, 乙", "开发: "])
        // 无日期 says which section a task is in.
        #expect(t.undated.map(\.title) == ["开发"])

        // 甲 down into 开发, on the same day.
        await m.applyTimelineEdit(try drop(m, [jia], on: today, into: t.lanes[1].target))
        try await settle(m)
        #expect(m.task(jia)?.sectionId == dev && m.task(jia)?.dueDate == today)

        // A click on 设计's empty lane adds a task there.
        let target = m.timelineNewTask(in: .list(work), on: today + 3, lane: t.lanes[0].target)
        let added = try #require(await m.quickAdd("评审", target: target))
        try await settle(m)
        #expect(m.task(added)?.sectionId == design && m.task(added)?.dueDate == today + 3)

        // ⌘-click 甲 and 乙, then drag 甲 a day on: both go.
        let order = m.timeline(for: .list(work)).lanes.flatMap { $0.bars.map(\.task.id) }
        m.tapOnTimeline(jia, modifiers: .command, order: order)
        m.tapOnTimeline(yi, modifiers: .command, order: order)
        #expect(m.selection.ids == [jia, yi])
        #expect(m.selectedTaskId == nil)
        await m.applyTimelineEdit(try drop(m, [jia, yi], on: today + 1, into: nil))
        try await settle(m)
        #expect(m.task(jia)?.dueDate == today + 1 && m.task(yi)?.dueDate == today + 2)
        // A plain click stops picking and opens the task.
        m.tapOnTimeline(yi, modifiers: [], order: order)
        #expect(!m.selection.isActive && m.selectedTaskId == yi)

        // By week, 显示已完成: kept for next time.
        m.settings.setTimelinePrefs(TimelinePrefs(scale: .week, showDone: true, trayOpen: false))
        let again = LocalSettings(m.database)
        #expect(again.timelinePrefs == TimelinePrefs(scale: .week, showDone: true, trayOpen: false))
    }

    @Test("finished tasks show when asked")
    func finished() async throws {
        let m = try await makeModel()
        let done = try await m.repo.addTask(title: "做完了", dueDate: today)
        _ = try await m.repo.addTask(title: "还没做", dueDate: today)
        _ = try await m.repo.setCompleted(done, true)
        try await settle(m)
        #expect(lanes(m.timeline(for: .smart(.inbox))) == ["null: 还没做"])
        m.settings.setTimelinePrefs(TimelinePrefs(showDone: true))
        #expect(lanes(m.timeline(for: .smart(.inbox))) == ["null: 还没做, 做完了"])
        // Ticking one back from the timeline.
        let finished = try #require(m.task(done))
        await m.setDone(finished, false)
        try await settle(m)
        #expect(m.task(done)?.status == .open)
    }

    @Test(arguments: ["timeline:list:work", "timeline:smart:today", "timeline:tag:会", "timeline:filter:f"])
    func viewRoutes(_ text: String) {
        #expect(DebugRoute(text)?.text == text)
        if case .timelineView? = DebugRoute(text) {} else { Issue.record("not a view route: \(text)") }
    }

    @Test func notViewRoutes() {
        #expect(DebugRoute("timeline:task:x") == nil)
        #expect(DebugRoute("timeline:smart:nope") == nil)
        #expect(DebugRoute("timeline:day") == .timelineDemo("day"))
    }
}
