// The arithmetic of the timeline, kept apart from the views so it can be
// tested: where the days are, which lane a point is in, where a dragged
// task lands and what dragging an edge does. Ported from the geometry and
// the drop handling of `app/lib/ui/timeline_view.dart`.
//
// Two kinds of x: *content* x counts from the left end of the scrollable
// strip (`origin`, ten years before the day it opened on); *viewport* x
// from the left edge of what's on screen (`contentX - scrollX`).

import Foundation
import OpenTodoDomain

enum TimelineMetrics {
    static let rowHeight = 32.0
    static let barHeight = 26.0
    /// Space above the first row of a lane.
    static let barTop = 4.0
    static let laneHeaderHeight = 30.0
    static let headerHeight = 44.0
    /// Room around a bar inside its days.
    static let barInset = 2.0
    /// A bar narrower than this has its title beside it instead of inside.
    static let titleInside = 88.0
    /// Narrower than this, a bar has no checkbox.
    static let checkboxInside = 20.0
    /// How far the timeline scrolls each way from where it opened.
    static let reachDays = 3650
    /// Space under the last lane.
    static let bottomPadding = 24.0

    static func dayWidth(_ s: TimelineScale) -> Double {
        switch s {
        case .day: 96
        case .week: 36
        case .month: 14
        }
    }

    /// Days before today on screen when the timeline goes to today.
    static func leadDays(_ s: TimelineScale) -> Int {
        switch s {
        case .day: 1
        case .week: 3
        case .month: 7
        }
    }
}

/// Where the days are at one scroll offset.
struct TimelineGeometry: Hashable {
    /// The day at content x 0.
    var origin: Day
    var scale: TimelineScale
    /// Content x at the left edge of the screen.
    var scrollX: Double
    /// How wide the screen is.
    var width: Double

    var dayWidth: Double { TimelineMetrics.dayWidth(scale) }

    /// The whole scrollable strip.
    var contentWidth: Double { Double(2 * TimelineMetrics.reachDays) * dayWidth }

    /// Where `day` starts, in content x.
    func contentX(_ day: Day) -> Double { Double(origin.days(to: day)) * dayWidth }

    /// Where `day` starts, from the left edge of the screen.
    func x(_ day: Day) -> Double { contentX(day) - scrollX }

    func day(atContentX x: Double) -> Day { origin + Int((x / dayWidth).rounded(.down)) }

    /// The day at `x` from the left edge of the screen.
    func dayAt(_ x: Double) -> Day { day(atContentX: x + scrollX) }

    var firstDay: Day { dayAt(0) }
    var lastDay: Day { dayAt(max(width - 0.01, 0)) }

    /// The content x that puts `day` at the left edge.
    func offset(leftDay day: Day) -> Double { contentX(day) }

    /// The day the screen shows at the left, rounding to the nearest (the
    /// toolbar names its month).
    var leftDay: Day { day(atContentX: scrollX + dayWidth / 2) }

    /// The origin for a timeline opened on `today`.
    static func origin(today: Day) -> Day { today - TimelineMetrics.reachDays }

    /// The scroll offset that keeps the left day when the scale changes; at
    /// today's usual place it stays there.
    static func offsetAfterScaleChange(
        from: TimelineScale, to: TimelineScale, scrollX: Double, origin: Day, home: Day
    ) -> Double {
        let left = scrollX / TimelineMetrics.dayWidth(from)
        let homeLeft = Double(origin.days(to: home - TimelineMetrics.leadDays(from)))
        if abs(left - homeLeft) < 0.01 {
            return Double(origin.days(to: home - TimelineMetrics.leadDays(to))) * TimelineMetrics.dayWidth(to)
        }
        return left * TimelineMetrics.dayWidth(to)
    }
}

/// Where the lanes are, top to bottom, in the vertical scroll's content.
struct TimelineLaneLayout: Hashable {
    struct Lane: Hashable {
        var top: Double
        /// 0 without a header.
        var header: Double
        /// 0 when folded.
        var body: Double
        var bottom: Double { top + header + body }
        var bodyTop: Double { top + header }
    }

    var lanes: [Lane]

    /// `rows` is how many rows each lane's bars take; `minHeight` is what a
    /// lone lane stretches to (so a click anywhere adds a task).
    init(rows: [Int], titled: Bool, collapsed: [Bool], minHeight: Double = 0) {
        var top = 0.0
        lanes = []
        for (i, n) in rows.enumerated() {
            let header = titled ? TimelineMetrics.laneHeaderHeight : 0
            let body = collapsed[i] ? 0 : Self.bodyHeight(rows: n, minHeight: rows.count == 1 ? minHeight : 0)
            lanes.append(Lane(top: top, header: header, body: body))
            top += header + body
        }
    }

    static func bodyHeight(rows: Int, minHeight: Double) -> Double {
        max(Double(max(rows, 1) + 1) * TimelineMetrics.rowHeight, minHeight)
    }

    /// The lane at `y`, header included.
    func lane(at y: Double) -> Int? {
        lanes.firstIndex { y >= $0.top && y < $0.bottom }
    }

    var height: Double { (lanes.last?.bottom ?? 0) + TimelineMetrics.bottomPadding }

    /// Top of a bar in row `row` of its lane's body.
    static func barTop(row: Int) -> Double {
        Double(row) * TimelineMetrics.rowHeight + (TimelineMetrics.rowHeight - TimelineMetrics.barHeight) / 2
            + TimelineMetrics.barTop
    }
}

/// Days from `start`, `days` of them: where a dragged task would land.
struct TimelineDropDays: Hashable {
    var start: Day
    var days: Int
    var last: Day { start + (days - 1) }
}

enum TimelineDragMath {
    /// The days a dragged task would cover if let go with the pointer over
    /// `under`: the part of its bar the pointer holds (`grabX` from the
    /// bar's left) stays under the pointer; a task without a date goes on
    /// the day under the pointer.
    static func dropDays(lead: TodoTask, under: Day, grabX: Double, dayWidth: Double) -> TimelineDropDays {
        guard lead.dueDate != nil else { return TimelineDropDays(start: under, days: 1) }
        let bar = TimelineBar(lead)
        let held = min(max(Int(((grabX + TimelineMetrics.barInset) / dayWidth).rounded(.down)), 0), bar.days - 1)
        return TimelineDropDays(start: under - held, days: bar.days)
    }

    /// The lane and days `dragged` (led by `lead`, held `grabX` from its
    /// bar's left) would land on with the pointer at content point
    /// (`contentX`, `contentY`, the vertical one in the lanes' scroll); nil
    /// over no lane, or one that takes none of them.
    static func landing(
        lanes: [TimelineLane], layout: TimelineLaneLayout, geometry: TimelineGeometry,
        contentX: Double, contentY: Double, lead: TodoTask, dragged: [TodoTask], grabX: Double
    ) -> (lane: Int, days: TimelineDropDays)? {
        guard let i = layout.lane(at: contentY), i < lanes.count else { return nil }
        let target = lanes[i].target
        guard dragged.contains(where: { takes($0, target) }) else { return nil }
        let under = geometry.day(atContentX: contentX)
        return (i, dropDays(lead: lead, under: under, grabX: grabX, dayWidth: geometry.dayWidth))
    }

    /// Whether a lane standing for `target` takes `t`.
    static func takes(_ t: TodoTask, _ target: GroupTarget?) -> Bool {
        isOpen(t) && (target?.takes(t) ?? true)
    }

    /// What letting go of `dragged` (led by `lead`) on a lane does; nil
    /// when the lane takes none of them.
    static func placement(dragged: [TodoTask], lead: TodoTask, drop: TimelineDropDays, target: GroupTarget?) -> TimelinePlacement? {
        let ids = dragged.filter { takes($0, target) }.map(\.id)
        if ids.isEmpty { return nil }
        let days = lead.dueDate.map { $0.days(to: drop.start) } ?? 0
        return TimelinePlacement(ids: ids, days: days, day: drop.start, target: target)
    }

    /// The tasks that lose their date when `dragged` is let go on 无日期:
    /// the open ones that have one.
    static func unscheduled(_ dragged: [TodoTask]) -> [String] {
        dragged.filter { isOpen($0) && $0.dueDate != nil }.map(\.id)
    }

    /// The day an edge of `bar` is on after being dragged `dx` points: the
    /// left one (`start`) never past the last day, the right one never
    /// before the first.
    static func resizedDay(_ bar: TimelineBar, start: Bool, dx: Double, dayWidth: Double) -> Day {
        let moved = (start ? bar.start : bar.last) + Int((dx / dayWidth).rounded())
        return start ? min(moved, bar.last) : max(moved, bar.start)
    }

    /// What letting go of an edge on `day` does; nil when it's back where
    /// it was.
    static func resizeEdit(_ task: TodoTask, start: Bool, day: Day) -> TimelineEdit? {
        let bar = TimelineBar(task)
        if day == (start ? bar.start : bar.last) { return nil }
        if start {
            let to = restartedSchedule(task, day)
            return .setStart(taskId: task.id, date: to.date, duration: to.duration)
        }
        return .setDuration(taskId: task.id, duration: resizedDuration(task, day))
    }

    /// How far to scroll each tick while something is dragged at
    /// `position` along a side `extent` long: towards an edge when within
    /// `edge` of it, faster the closer; 0 otherwise.
    static func autoScrollStep(position: Double, extent: Double, edge: Double = 44, maxStep: Double = 18) -> Double {
        guard extent > 2 * edge else { return 0 }
        if position < edge { return -maxStep * min(1, (edge - position) / edge) }
        if position > extent - edge { return maxStep * min(1, (position - (extent - edge)) / edge) }
        return 0
    }

    /// The day at the left edge when the timeline opens or goes to today:
    /// a day or few before today; for 今天 and the other date views, early
    /// enough to show the earliest overdue task (`earliestOverdue`).
    static func homeLeftDay(today: Day, scale: TimelineScale, earliestOverdue: Day? = nil) -> Day {
        let usual = today - TimelineMetrics.leadDays(scale)
        guard let earliestOverdue else { return usual }
        return min(usual, earliestOverdue - 1)
    }

    /// The earliest first day among the open bars that begin before today.
    static func earliestOverdue(_ timeline: Timeline, today: Day) -> Day? {
        timeline.lanes.flatMap(\.bars).filter { !$0.done && $0.start < today }.map(\.start).min()
    }

    /// How far a bar's title moves right so it stays on screen while the
    /// bar's start has scrolled off to the left: never past the bar's end
    /// less `keep` points.
    static func stickyTitleOffset(barLeft: Double, barWidth: Double, keep: Double = 60) -> Double {
        min(max(-barLeft, 0), max(barWidth - keep, 0))
    }
}
