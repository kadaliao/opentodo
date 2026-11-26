// The timeline component's arithmetic: where the days and lanes are, and
// what a drag (from the point it's let go) turns into. The drags
// themselves can't be screenshotted, so the steps from a pointer position
// to the edit handed to the caller are checked here.

import Foundation
import OpenTodoDomain
import Testing
@testable import OpenTodoUI

private let today = Day(2026, 11, 15) // Sunday

private func task(
    _ id: String, list: String = "w", section: String? = nil, due: Int? = nil, time: Int? = nil,
    duration: Int? = nil, done: Bool = false
) -> TodoTask {
    TodoTask(
        id: id, listId: list, sectionId: section, title: id, dueDate: due.map { today + $0 },
        dueTime: time, duration: duration, status: done ? .done : .open
    )
}

private func geometry(_ scale: TimelineScale = .day, leftDay: Day = Day(2026, 11, 14), width: Double = 960) -> TimelineGeometry {
    let origin = TimelineGeometry.origin(today: today)
    var g = TimelineGeometry(origin: origin, scale: scale, scrollX: 0, width: width)
    g.scrollX = g.offset(leftDay: leftDay)
    return g
}

@Suite("timeline layout")
struct TimelineLayoutTests {
    @Test("days along the strip, from either kind of x")
    func days() {
        let g = geometry()
        #expect(g.origin == today - 3650)
        #expect(g.contentWidth == 700_800.0)
        #expect(g.firstDay == Day(2026, 11, 14))
        #expect(g.x(Day(2026, 11, 15)) == 96)
        #expect(g.dayAt(95.9) == Day(2026, 11, 14))
        #expect(g.dayAt(96) == today)
        #expect(g.dayAt(-1) == Day(2026, 11, 13))
        #expect(g.lastDay == Day(2026, 11, 23)) // 960 / 96 = 10 days
        #expect(g.day(atContentX: g.contentX(Day(2027, 3, 1)) + 50) == Day(2027, 3, 1))
        // The toolbar's month: the day mostly on screen at the left.
        var h = g
        h.scrollX += 60
        #expect(h.leftDay == today)
    }

    @Test("changing the scale keeps the left day, or today's usual place")
    func scaleChange() {
        let origin = TimelineGeometry.origin(today: today)
        // At home (a day before today, by day) → home by week (three days before).
        let home = Double(origin.days(to: today - 1)) * 96
        let x = TimelineGeometry.offsetAfterScaleChange(from: .day, to: .week, scrollX: home, origin: origin, home: today)
        #expect(x == Double(origin.days(to: today - 3)) * 36)
        // Elsewhere: the same day at the left.
        let away = Double(origin.days(to: Day(2027, 1, 1))) * 96
        let y = TimelineGeometry.offsetAfterScaleChange(from: .day, to: .month, scrollX: away, origin: origin, home: today)
        #expect(y == Double(origin.days(to: Day(2027, 1, 1))) * 14)
    }

    @Test("lanes stack: header, then rows and one spare; folded ones are just the header")
    func lanes() {
        let l = TimelineLaneLayout(rows: [2, 0, 1], titled: true, collapsed: [false, true, false])
        let tops: [Double] = [0, 126, 156]
        #expect(l.lanes.map(\.top) == tops)
        let bodies: [Double] = [96, 0, 64]
        #expect(l.lanes.map(\.body) == bodies)
        #expect(l.lane(at: 0) == 0)
        #expect(l.lane(at: 125.9) == 0)
        #expect(l.lane(at: 126) == 1)
        #expect(l.lane(at: 156) == 2)
        #expect(l.lane(at: 250) == nil)
        #expect(l.height == 274.0)
        // A lone lane fills the screen; with several, none stretches.
        #expect(TimelineLaneLayout(rows: [1], titled: false, collapsed: [false], minHeight: 500).lanes[0].body == 500)
        #expect(TimelineLaneLayout(rows: [1, 1], titled: false, collapsed: [false, false], minHeight: 500).lanes[0].body == 64)
        #expect(TimelineLaneLayout.barTop(row: 1) == 39.0)
    }

    @Test("a dragged bar keeps the day it's held by under the pointer")
    func dropDays() {
        let trip = task("出差", due: 0, duration: 3 * minutesPerDay) // 15..17
        // Held by its second day (96 + a bit from its left), pointer over the 20th.
        let d = TimelineDragMath.dropDays(lead: trip, under: Day(2026, 11, 20), grabX: 100, dayWidth: 96)
        #expect(d == TimelineDropDays(start: Day(2026, 11, 19), days: 3))
        #expect(d.last == Day(2026, 11, 21))
        // Held past its end (the title beside it): its last day.
        #expect(TimelineDragMath.dropDays(lead: trip, under: Day(2026, 11, 20), grabX: 500, dayWidth: 96).start == Day(2026, 11, 18))
        // A task without a date: on the day under the pointer.
        let idea = task("想法")
        #expect(TimelineDragMath.dropDays(lead: idea, under: Day(2026, 11, 20), grabX: 100, dayWidth: 96)
            == TimelineDropDays(start: Day(2026, 11, 20), days: 1))
    }

    @Test("pointer to lane and days to the edit: moved days, the lane's target, only what it takes")
    func landing() throws {
        let lanes = [
            TimelineLane("s1", "本周", .section(listId: "w", sectionId: "s1"), []),
            TimelineLane("other", "生活", .list("home"), []),
            TimelineLane("s2", "下周", .section(listId: "w", sectionId: "s2"), []),
        ]
        let layout = TimelineLaneLayout(rows: [1, 1, 1], titled: true, collapsed: [false, false, false])
        let g = geometry()
        let meeting = task("会", section: "s1", due: 0, time: 9 * 60, duration: 90)
        let done = task("完成了", section: "s1", due: 0, done: true)
        let other = task("别的清单", list: "x", due: 2)
        // Into 下周 (third lane), on the 18th, held by its start.
        let x = g.contentX(Day(2026, 11, 18)) + 10
        let y = layout.lanes[2].bodyTop + 10
        let land = try #require(TimelineDragMath.landing(
            lanes: lanes, layout: layout, geometry: g, contentX: x, contentY: y,
            lead: meeting, dragged: [meeting, done, other], grabX: 5
        ))
        #expect(land.lane == 2)
        let p = try #require(TimelineDragMath.placement(dragged: [meeting, done, other], lead: meeting, drop: land.days, target: lanes[2].target))
        // Finished ones don't move; a section takes only its own list's tasks.
        #expect(p == TimelinePlacement(ids: ["会"], days: 3, day: Day(2026, 11, 18), target: .section(listId: "w", sectionId: "s2")))
        // A list lane takes any open task.
        let q = TimelineDragMath.placement(dragged: [meeting, other], lead: other, drop: TimelineDropDays(start: Day(2026, 11, 16), days: 1), target: .list("home"))
        #expect(q == TimelinePlacement(ids: ["会", "别的清单"], days: -1, day: Day(2026, 11, 16), target: .list("home")))
        // Nothing it takes: no landing at all.
        #expect(TimelineDragMath.landing(lanes: lanes, layout: layout, geometry: g, contentX: x, contentY: y,
                                         lead: other, dragged: [other], grabX: 5) == nil)
        // Below the last lane: nowhere.
        #expect(TimelineDragMath.landing(lanes: lanes, layout: layout, geometry: g, contentX: x, contentY: 10_000,
                                         lead: meeting, dragged: [meeting], grabX: 5) == nil)
        // An undated task lands on the day, without moving the others' days.
        let idea = task("想法")
        let r = TimelineDragMath.placement(dragged: [idea], lead: idea, drop: TimelineDropDays(start: Day(2026, 11, 20), days: 1), target: nil)
        #expect(r == TimelinePlacement(ids: ["想法"], days: 0, day: Day(2026, 11, 20), target: nil))
    }

    @Test("onto 无日期: the open ones with a date lose it")
    func unscheduled() {
        #expect(TimelineDragMath.unscheduled([task("a", due: 0), task("b"), task("c", due: 1, done: true)]) == ["a"])
    }

    @Test("dragging an edge: rounded to days, never past the other end; the edit uses the domain's maths")
    func edges() {
        let t = task("会", due: 0, time: 9 * 60, duration: 120)
        let bar = TimelineBar(t)
        #expect(TimelineDragMath.resizedDay(bar, start: false, dx: 150, dayWidth: 96) == Day(2026, 11, 17))
        #expect(TimelineDragMath.resizedDay(bar, start: false, dx: -300, dayWidth: 96) == today)
        #expect(TimelineDragMath.resizedDay(bar, start: true, dx: -200, dayWidth: 96) == Day(2026, 11, 13))
        #expect(TimelineDragMath.resizedDay(bar, start: true, dx: 300, dayWidth: 96) == today)

        #expect(TimelineDragMath.resizeEdit(t, start: false, day: Day(2026, 11, 17))
            == .setDuration(taskId: "会", duration: 2 * minutesPerDay + 120))
        #expect(TimelineDragMath.resizeEdit(t, start: true, day: Day(2026, 11, 13))
            == .setStart(taskId: "会", date: Day(2026, 11, 13), duration: 2 * minutesPerDay + 120))
        // Let go where it was: nothing.
        #expect(TimelineDragMath.resizeEdit(t, start: false, day: today) == nil)
        #expect(TimelineDragMath.resizeEdit(t, start: true, day: today) == nil)
        // An all-day task dragged back to one day: no span.
        let span = task("三天", due: 0, duration: 3 * minutesPerDay)
        #expect(TimelineDragMath.resizeEdit(span, start: false, day: today) == .setDuration(taskId: "三天", duration: nil))
    }

    @Test("near an edge while dragging: scroll that way, faster the closer")
    func autoScroll() {
        #expect(TimelineDragMath.autoScrollStep(position: 300, extent: 800) == 0)
        #expect(TimelineDragMath.autoScrollStep(position: 0, extent: 800) == -18)
        #expect(TimelineDragMath.autoScrollStep(position: 22, extent: 800) == -9)
        #expect(TimelineDragMath.autoScrollStep(position: 800, extent: 800) == 18)
        #expect(TimelineDragMath.autoScrollStep(position: 900, extent: 800) == 18)
        #expect(TimelineDragMath.autoScrollStep(position: 10, extent: 60) == 0) // too small to tell
    }

    @Test("opening: today a day or few in; 今天 and the like from the earliest overdue task")
    func home() {
        #expect(TimelineDragMath.homeLeftDay(today: today, scale: .day) == today - 1)
        #expect(TimelineDragMath.homeLeftDay(today: today, scale: .month) == today - 7)
        #expect(TimelineDragMath.homeLeftDay(today: today, scale: .day, earliestOverdue: today - 4) == today - 5)
        #expect(TimelineDragMath.homeLeftDay(today: today, scale: .month, earliestOverdue: today - 4) == today - 7)

        let tl = buildViewTimeline(.smart(.today), [
            task("旧", due: -6, done: true), task("过期", due: -3), task("跨着", due: -2, duration: 3 * minutesPerDay), task("今天", due: 0),
        ], now: LocalDateTime(today, minute: 600), showDone: true)
        #expect(TimelineDragMath.earliestOverdue(tl, today: today) == today - 3)
    }

    @Test("a bar's title stays on screen while its start is scrolled off")
    func sticky() {
        #expect(TimelineDragMath.stickyTitleOffset(barLeft: 40, barWidth: 300) == 0)
        #expect(TimelineDragMath.stickyTitleOffset(barLeft: -100, barWidth: 300) == 100)
        // Never past its end (less room for the title).
        #expect(TimelineDragMath.stickyTitleOffset(barLeft: -280, barWidth: 300) == 240)
    }

    @Test(arguments: TimelineDemo.Scene.allCases)
    func debugRoutes(_ scene: TimelineDemo.Scene) {
        let text = "timeline:\(scene.rawValue)"
        #expect(DebugRoute(text) == .timelineDemo(scene.rawValue))
        #expect(DebugRoute(text)?.text == text)
    }

    @Test func unknownDemoSceneIsNoRoute() {
        #expect(DebugRoute("timeline:nope") == nil)
        #expect(DebugRoute("timeline") == .timeline)
    }
}
