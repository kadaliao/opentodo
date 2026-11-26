// Ported from `app/test/timeline_test.dart`. The group "dropping on the
// timeline" runs through `TaskRepo` (`placeOnTimeline`, `setStart`) and
// belongs to the data layer.

import Testing
@testable import OpenTodoDomain

func section(_ id: String, _ name: String, _ order: Double, listId: String = "w") -> ListSection {
    ListSection(id: id, listId: listId, name: name, sortOrder: order, dirty: false)
}

func inSection(_ t: TodoTask, _ sectionId: String?) -> TodoTask {
    var t = t
    t.sectionId = sectionId
    return t
}

/// `title start..last` for each bar of each row.
private func shapeRows(_ rows: [[TimelineBar]]) -> [[String]] {
    rows.map { $0.map { "\($0.task.title) \($0.start.day)..\($0.last.day)" } }
}

private func d(_ day: Int) -> Day { Day(2026, 11, day) }

@Suite("timeline")
struct TimelineTests {
    // MARK: bars

    @Test("bars: cover the days a task is on")
    func barDays() {
        #expect(TimelineBar(makeTask("一天", due: "2026-11-15")).days == 1)
        // An all-day span of three days.
        let allDay = TimelineBar(makeTask("三天", due: "2026-11-15", duration: 3 * minutesPerDay))
        #expect(allDay.start == Day(2026, 11, 15) && allDay.last == Day(2026, 11, 17) && allDay.days == 3)
        // 22:00 for three hours ends the next day; ending at midnight doesn't.
        #expect(TimelineBar(makeTask("过夜", due: "2026-11-15", time: 22 * 60, duration: 180)).days == 2)
        #expect(TimelineBar(makeTask("到半夜", due: "2026-11-15", time: 22 * 60, duration: 120)).days == 1)
    }

    @Test("bars: overlap a range of days")
    func overlap() {
        let b = TimelineBar(makeTask("三天", due: "2026-11-15", duration: 3 * minutesPerDay))
        #expect(b.overlaps(d(17), d(20)))
        #expect(b.overlaps(d(10), d(15)))
        #expect(!b.overlaps(d(18), d(20)))
        #expect(!b.overlaps(d(10), d(14)))
        #expect(b.description == "三天 2026-11-15..2026-11-17")
    }

    // MARK: lanes

    struct Lanes {
        let sections = [section("s2", "下周", 2), section("s1", "本周", 1)]
        let tasks = [
            inSection(makeTask("甲", listId: "w", due: "2026-11-16"), "s1"),
            inSection(makeTask("乙", listId: "w", due: "2026-11-15"), "s1"),
            inSection(makeTask("丙", listId: "w", due: "2026-11-23"), "s2"),
            inSection(makeTask("想法", listId: "w"), "s2"),
            makeTask("散的", listId: "w"),
            makeTask("完成了", listId: "w", due: "2026-11-14", status: .done, completedAt: 1),
            makeTask("删了", listId: "w", due: "2026-11-14", trashedAt: 1),
            makeTask("别的清单", listId: "x", due: "2026-11-14"),
            // A section that's gone: 未分组.
            inSection(makeTask("旧分组", listId: "w", due: "2026-11-20"), "gone"),
        ]
    }

    private func titles(_ l: TimelineLane) -> String {
        "\(l.title ?? "null"): \(l.bars.map(\.task.title).joined(separator: ", "))"
    }

    @Test("lanes: one per section, in order, bars by first day")
    func lanes() {
        let x = Lanes()
        let t = buildTimeline("w", x.tasks, x.sections)
        #expect(t.lanes.map(titles) == ["未分组: 旧分组", "本周: 乙, 甲", "下周: 丙"])
        // Undated open tasks wait beside it, by section.
        #expect(t.undated.map { "\($0.title ?? "null"): \($0.tasks.map(\.title).joined(separator: ", "))" }
            == ["未分组: 散的", "下周: 想法"])
        #expect(t.undatedTasks.map(\.title) == ["散的", "想法"])
    }

    @Test("lanes: finished tasks only when asked, after open ones on the same day")
    func finished() {
        let x = Lanes()
        let more = x.tasks + [makeTask("同一天", listId: "w", due: "2026-11-14")]
        let t = buildTimeline("w", more, x.sections, showDone: true)
        #expect(titles(t.lanes[0]) == "未分组: 同一天, 完成了, 旧分组")
        #expect(buildTimeline("w", more, x.sections).lanes[0].bars.map(\.task.title) == ["同一天", "旧分组"])
    }

    @Test("lanes: 未分组 shows only with dated tasks, unless the list has no sections")
    func looseLane() {
        let x = Lanes()
        let noLoose = x.tasks.filter { $0.sectionId == "s1" || $0.sectionId == "s2" }
        #expect(buildTimeline("w", noLoose, x.sections).lanes.map(\.title) == ["本周", "下周"])
        // Its undated tasks still wait beside.
        #expect(buildTimeline("w", noLoose + [makeTask("散的", listId: "w")], x.sections).undated.first?.title == "未分组")
        let plain = buildTimeline("w", [makeTask("散的", listId: "w")], [])
        #expect(plain.lanes.map(titles) == ["null: "]) // no header without sections
    }

    @Test("lanes: on the same day, in the list's order")
    func sameDay() {
        let a = makeTask("先加的", listId: "w", due: "2026-11-15", priority: .low)
        let b = makeTask("后加的", listId: "w", due: "2026-11-15", priority: .high)
        // Manual order: newest first (the helper's sortOrder).
        #expect(buildTimeline("w", [a, b], []).lanes.map { $0.bars.map(\.task.title) } == [["后加的", "先加的"]])
        #expect(buildTimeline("w", [a, b], [], sort: .title).lanes.map { $0.bars.map(\.task.title) }
            == [["后加的", "先加的"]]) // hou, xian
    }

    // MARK: rows

    var bars: [TimelineBar] {
        [
            TimelineBar(makeTask("长", due: "2026-11-15", duration: 4 * minutesPerDay)), // 15..18
            TimelineBar(makeTask("甲", due: "2026-11-16")),
            TimelineBar(makeTask("乙", due: "2026-11-17")),
            TimelineBar(makeTask("丙", due: "2026-11-19")),
            TimelineBar(makeTask("丁", due: "2026-11-19")),
        ]
    }

    @Test("rows: each bar in the first row with room")
    func rows() {
        #expect(shapeRows(packRows(bars)) == [
            ["长 15..18", "丙 19..19"],
            ["甲 16..16", "乙 17..17", "丁 19..19"],
        ])
    }

    @Test("rows: a bar takes room for its title when the days are narrow")
    func narrowRows() {
        #expect(shapeRows(packRows(bars, minDays: 3)) == [
            ["长 15..18", "丙 19..19"],
            ["甲 16..16", "丁 19..19"],
            ["乙 17..17"],
        ])
    }

    // MARK: dragging the right edge

    @Test("dragging the right edge: an all-day task covers whole days")
    func rightAllDay() {
        let t = makeTask("全天", due: "2026-11-15")
        #expect(resizedDuration(t, d(17)) == 3 * minutesPerDay)
        #expect(resizedDuration(t, d(15)) == nil)
        // Never before its first day.
        #expect(resizedDuration(t, d(12)) == nil)
        let span = makeTask("三天", due: "2026-11-15", duration: 3 * minutesPerDay)
        #expect(resizedDuration(span, d(16)) == 2 * minutesPerDay)
        #expect(resizedDuration(span, d(15)) == nil)
    }

    @Test("dragging the right edge: a timed task ends at the same time on the new day")
    func rightTimed() {
        // 9:00-11:00 → 9:00 to 11:00 two days later.
        let t = makeTask("会", due: "2026-11-15", time: 9 * 60, duration: 120)
        #expect(resizedDuration(t, d(17)) == 2 * minutesPerDay + 120)
        #expect(resizedDuration(t, d(15)) == 120)
        // And back again.
        let long = makeTask("会", due: "2026-11-15", time: 9 * 60, duration: 2 * minutesPerDay + 120)
        #expect(resizedDuration(long, d(15)) == 120)
        #expect(resizedDuration(long, d(16)) == minutesPerDay + 120)
        // A moment becomes a span to the same time.
        let moment = makeTask("点", due: "2026-11-15", time: 9 * 60)
        #expect(resizedDuration(moment, d(16)) == minutesPerDay)
        #expect(resizedDuration(moment, d(15)) == nil)
    }

    @Test("dragging the right edge: a timed task that can't keep its end time ends with the day")
    func rightEndOfDay() throws {
        // At midnight for no time: to the next day, it ends at the end of it.
        let midnight = makeTask("零点", due: "2026-11-15", time: 0)
        let d1 = try #require(resizedDuration(midnight, d(16)))
        #expect(spanLastDay(day("2026-11-15"), 0, d1) == d(16))
        #expect(d1 == 2 * minutesPerDay)
        // 23:00 for two hours, back onto its first day: no span.
        let late = makeTask("夜", due: "2026-11-15", time: 23 * 60, duration: 120)
        #expect(resizedDuration(late, d(15)) == nil)
        #expect(spanLastDay(day("2026-11-15"), 23 * 60, resizedDuration(late, d(17))) == d(17))
    }

    // MARK: dragging the left edge

    private func shape(_ s: (date: Day, duration: Int?)) -> String {
        "\(s.date.key) \(s.duration.map(String.init) ?? "null")"
    }

    @Test("dragging the left edge: an all-day task still ends on its last day")
    func leftAllDay() {
        let t = makeTask("全天", due: "2026-11-15")
        // Two days earlier: three days to the 15th.
        #expect(shape(restartedSchedule(t, d(13))) == "2026-11-13 \(3 * minutesPerDay)")
        #expect(shape(restartedSchedule(t, d(15))) == "2026-11-15 null")
        // Never past its last day.
        #expect(shape(restartedSchedule(t, d(18))) == "2026-11-15 null")
        let span = makeTask("三天", due: "2026-11-15", duration: 3 * minutesPerDay) // 15..17
        #expect(shape(restartedSchedule(span, d(16))) == "2026-11-16 \(2 * minutesPerDay)")
        #expect(shape(restartedSchedule(span, d(17))) == "2026-11-17 null")
        #expect(shape(restartedSchedule(span, d(20))) == "2026-11-17 null")
    }

    @Test("dragging the left edge: a timed task keeps its time of day and its end")
    func leftTimed() {
        // 9:00-11:00 on the 15th, started two days earlier: 9:00 on the 13th
        // to 11:00 on the 15th.
        let t = makeTask("会", due: "2026-11-15", time: 9 * 60, duration: 120)
        #expect(shape(restartedSchedule(t, d(13))) == "2026-11-13 \(2 * minutesPerDay + 120)")
        // And back.
        let long = makeTask("会", due: "2026-11-13", time: 9 * 60, duration: 2 * minutesPerDay + 120)
        #expect(shape(restartedSchedule(long, d(15))) == "2026-11-15 120")
        // A moment becomes a span that ends at it.
        let moment = makeTask("点", due: "2026-11-15", time: 9 * 60)
        #expect(shape(restartedSchedule(moment, d(14))) == "2026-11-14 \(minutesPerDay)")
        // 22:00 to 6:00 the next day, started on the next day: 22:00 is after
        // 6:00, so no span.
        let night = makeTask("夜班", due: "2026-11-15", time: 22 * 60, duration: 8 * 60)
        #expect(shape(restartedSchedule(night, d(16))) == "2026-11-16 null")
    }

    // MARK: timelines of other views

    struct Others {
        let lists = ["w": TaskList(id: "w", name: "工作", sortOrder: 1, dirty: false)]
        let tasks = [
            makeTask("晨会", listId: "w", due: "2026-11-15", tags: ["会"]),
            makeTask("交房租", due: "2026-11-14", priority: .high),
            makeTask("下周", listId: "w", due: "2026-11-20", tags: ["会"]),
            makeTask("想法", listId: "w", tags: ["会"]),
            makeTask("完成了", due: "2026-11-15", status: .done, completedAt: 1),
        ]
    }

    private func lanes(_ t: Timeline) -> String {
        t.lanes.map { "\($0.title ?? "null"): \($0.bars.map(\.task.title).joined(separator: ", "))" }
            .joined(separator: " / ")
    }

    @Test("other views: 今天 goes by list by default (not by date), and has no 无日期")
    func today() {
        let x = Others()
        let t = buildViewTimeline(.smart(.today), x.tasks, now: testNow, lists: x.lists)
        #expect(lanes(t) == "收集箱: 交房租 / 工作: 晨会")
        #expect(t.lanes.compactMap { l -> String? in if case .list(let id)? = l.target { id } else { nil } } == [inboxListId, "w"])
        #expect(!t.takesUndated)
        #expect(t.undated.isEmpty)
        // By date, as the list shows it, is no lanes at all on a timeline.
        let byDate = buildViewTimeline(.smart(.today), x.tasks, now: testNow, lists: x.lists, grouping: .date)
        #expect(lanes(byDate) == lanes(t))
        let none = buildViewTimeline(.smart(.today), x.tasks, now: testNow, lists: x.lists, grouping: TaskGrouping.none)
        #expect(lanes(none) == "null: 交房租, 晨会")
        #expect(!none.titled)
        // Finished ones when asked.
        let done = buildViewTimeline(.smart(.today), x.tasks, now: testNow, lists: x.lists, grouping: TaskGrouping.none, showDone: true)
        #expect(lanes(done) == "null: 交房租, 晨会, 完成了")
    }

    @Test("other views: a tag: undated tasks wait beside, in a lane of their own group")
    func tag() {
        let x = Others()
        let t = buildViewTimeline(.tag("会"), x.tasks, now: testNow, lists: x.lists)
        #expect(lanes(t) == "工作: 晨会, 下周")
        #expect(t.undated.map { "\($0.title ?? "null"): \($0.tasks.map(\.title).joined(separator: ", "))" } == ["工作: 想法"])
        // A group with only undated tasks still has its lane, to drag them
        // onto without leaving it.
        let onlyIdea = buildViewTimeline(.tag("会"), [x.tasks[3]], now: testNow, lists: x.lists)
        #expect(lanes(onlyIdea) == "工作: ")
        // By priority.
        let byPriority = buildViewTimeline(.tag("会"), x.tasks, now: testNow, lists: x.lists, grouping: .priority)
        #expect(lanes(byPriority) == "无优先级: 晨会, 下周")
    }

    @Test("other views: nothing to show is still one lane, to click on")
    func empty() {
        let x = Others()
        let t = buildViewTimeline(.tag("空"), x.tasks, now: testNow, lists: x.lists)
        #expect(t.lanes.count == 1)
        #expect(t.lanes.first?.title == nil)
        #expect(t.lanes.first?.bars.isEmpty == true)
    }

    @Test("other views: a list is its sections, whatever the grouping")
    func aList() {
        let x = Others()
        let t = buildViewTimeline(.list("w"), x.tasks, now: testNow, lists: x.lists, grouping: .tag)
        #expect(lanes(t) == "null: 晨会, 下周")
        #expect(t.lanes.count == 1)
        #expect(targetKind(t.lanes.first?.target) == "SectionTarget")
    }

    @Test("other views: a task added on a lane starts with what the lane stands for")
    func laneNew() {
        let today = Day(2026, 11, 15)
        #expect(laneNewTask(.smart(.today), .list("w"), today).listId == "w")
        let tag = laneNewTask(.tag("会"), .priority(.high), today)
        #expect(tag.listId == inboxListId && tag.tags == ["会"] && tag.priority == .high)
        let section = laneNewTask(.list("w"), .section(listId: "w", sectionId: "s1"), today)
        #expect(section.listId == "w" && section.sectionId == "s1")
        #expect(laneNewTask(.tag("会"), nil, today).tags == ["会"])
    }

    @Test("the month label")
    func monthLabel() {
        #expect(timelineMonthLabel(Day(2026, 11, 20)) == "2026年11月")
    }

    // Not in the Dart test.
    @Test("scales")
    func scales() {
        #expect(TimelineScale.byName("week") == .week)
        #expect(TimelineScale.byName(3) == nil && TimelineScale.byName(nil) == nil)
        #expect(TimelineScale.allCases.map(\.minDays) == [1, 4, 10])
        #expect(TimelineScale.month.label == "月")
    }
}
