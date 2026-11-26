// The calendar screen's decisions, apart from drawing: what a click on a
// task does (open it, or pick it for 多选), the single-key commands, where
// a point on the hour grid or a month row falls, when a drop is no move at
// all, and how many tasks a month cell has room for. Ported from the
// Flutter version's `state/selection.dart` (`TaskSelection`, `tapTask`),
// `ui/calendar/*.dart` and `calendar_screen.dart`; pure, so the unit tests
// pin them down where screenshots can't (drags, keys).

import CoreGraphics
import OpenTodoDomain

public enum CalendarLogic {}

// MARK: - Commands and keys

/// Something the person asks the calendar to do from the keyboard, the
/// toolbar or a menu.
public enum CalendarCommand: Sendable, Hashable {
    case mode(CalendarMode)
    case today
    case page(Int)
    case selectAll
    case clearPicking
}

/// The single keys of the calendar on a computer (Dart's
/// `_CalendarShortcuts`): D 3 W M A for the modes (Y for the year view,
/// which the Flutter version hasn't got), T for today, ← → to turn pages,
/// ⌘A to pick every task on the page, Esc to stop picking.
public enum CalendarKey: Sendable, Hashable {
    case character(Character)
    case left, right, escape
}

extension CalendarLogic {

    public static func command(for key: CalendarKey, command: Bool = false) -> CalendarCommand? {
        switch key {
        case .left: return command ? nil : .page(-1)
        case .right: return command ? nil : .page(1)
        case .escape: return .clearPicking
        case .character(let c):
            let lower = Character(c.lowercased())
            if command { return lower == "a" ? .selectAll : nil }
            switch lower {
            case "d": return .mode(.day)
            case "3": return .mode(.threeDays)
            case "w": return .mode(.week)
            case "m": return .mode(.month)
            case "a": return .mode(.agenda)
            case "y": return .mode(.year)
            case "t": return .today
            default: return nil
            }
        }
    }

    /// The key shown beside each mode in the mode menu.
    public static func modeKey(_ mode: CalendarMode) -> String? {
        switch mode {
        case .day: "D"
        case .threeDays: "3"
        case .week: "W"
        case .month: "M"
        case .agenda: "A"
        case .year: "Y"
        case .multiWeek: nil
        }
    }

    /// SF Symbol for each mode, for menus and the iPhone's mode button.
    public static func modeSymbol(_ mode: CalendarMode) -> String {
        switch mode {
        case .day: "calendar.day.timeline.left"
        case .threeDays: "rectangle.split.3x1"
        case .week: "calendar.day.timeline.leading"
        case .month: "calendar"
        case .agenda: "list.bullet.below.rectangle"
        case .year: "square.grid.3x3"
        case .multiWeek: "rectangle.grid.1x2"
        }
    }

    /// The order the modes are offered in: the hour grids, then the grids of
    /// days, then the lists.
    public static let modesOffered: [CalendarMode] = [.day, .threeDays, .week, .multiWeek, .month, .year, .agenda]

    /// The modes a narrow screen (an iPhone upright) offers: no week or
    /// multi-week, whose seven columns are too narrow there to read a task
    /// in — as the system Calendar offers neither on a phone held upright.
    public static func modesOffered(compact: Bool) -> [CalendarMode] {
        compact ? modesOffered.filter { $0 != .week && $0 != .multiWeek } : modesOffered
    }

    /// The mode shown for the stored `mode`: on a narrow screen a week falls
    /// back to 3 days and multi-week to the month (the stored choice stays,
    /// for the wide window).
    public static func shownMode(_ mode: CalendarMode, compact: Bool) -> CalendarMode {
        guard compact else { return mode }
        switch mode {
        case .week: return .threeDays
        case .multiWeek: return .month
        default: return mode
        }
    }
}

// MARK: - Hour grid geometry

public enum CalendarMetrics {
    /// The hour grid's height of an hour, as the Flutter version.
    public static let hourHeight: CGFloat = 48
    /// A task bar in a month cell or the all-day row.
    public static let chipHeight: CGFloat = 20
    public static let chipGap: CGFloat = 2
    /// The day number and lunar note at the top of a month cell.
    public static let cellHeader: CGFloat = 26
    /// A drop closer than this to where the drag began moves nothing: a
    /// long press let go without moving, or a nudge.
    public static let inPlaceDistance: CGFloat = 8
}

extension CalendarLogic {

    /// The y of `minute` on the hour grid.
    public static func gridY(_ minute: Int) -> CGFloat { CGFloat(minute) / 60 * CalendarMetrics.hourHeight }

    /// The minute at `y`, snapped down to `step` and kept in the day (what a
    /// drop or a click lands on).
    public static func gridMinute(atY y: CGFloat, step: Int = 15) -> Int {
        snapMinutes(Double(y / CalendarMetrics.hourHeight * 60), step: step)
    }

    /// Whether a drag let go at `end` is where it began (`start`): nothing
    /// moves. Dart's `droppedInPlace`.
    public static func droppedInPlace(_ start: CGPoint, _ end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) < CalendarMetrics.inPlaceDistance
    }

    /// Where a task dragged on the hour grid lands: the top of the dragged bar
    /// is where it was (`barTop`) plus how far the pointer has moved, snapped
    /// down to 15 minutes. A bar dragged in from elsewhere (the all-day row,
    /// the 安排任务 panel) has its top at the pointer.
    public static func dropMinute(pointerY: CGFloat, startPointerY: CGFloat?, barTop: CGFloat?) -> Int {
        guard let startPointerY, let barTop else { return gridMinute(atY: pointerY) }
        return gridMinute(atY: barTop + (pointerY - startPointerY))
    }

    /// The end a task's bottom edge is dragged to, `dy` points from where it
    /// was: snapped to 15 minutes, at least 15 after the start, at most
    /// midnight. Returns minutes after midnight of the entry's day.
    public static func resizedEnd(start: Int, end: Int, dy: CGFloat) -> Int {
        let steps = (Double(dy / CalendarMetrics.hourHeight) * 60 / 15).rounded()
        return min(max(end + Int(steps) * 15, start + 15), minutesPerDay)
    }

    /// The task's new duration when the bottom edge of its entry `e` ends at
    /// `end` (minutes after midnight of the entry's day).
    public static func durationForEnd(_ e: CalendarEntry, end: Int) -> Int? {
        guard let dueTime = e.task.dueTime else { return nil }
        return e.dayIndex * minutesPerDay + end - dueTime
    }

    /// Whether an entry can be dragged, resized or ticked: only a task's own
    /// date, not a later one of a repeating task, and only while it is open.
    public static func canMoveEntry(_ e: CalendarEntry) -> Bool { !e.projected && !e.done && e.task.trashedAt == nil }

    /// What the hover box on the hour grid says while tasks are dragged over
    /// it: 09:00, or 09:00 · 3 项 for several.
    public static func hoverLabel(minute: Int, count: Int) -> String {
        count > 1 ? "\(clockLabel(minute)) · \(count) 项" : clockLabel(minute)
    }

    /// Where the hour grid opens: two hours before now when today is shown,
    /// otherwise 7:00.
    public static func initialScrollMinute(range: DayRange, now: LocalDateTime) -> Int {
        range.contains(now.day) ? max(now.minuteOfDay - 120, 0) : 7 * 60
    }

    /// How many lines of the all-day row to show: as many as the busiest day
    /// needs, at least one, at most 6 for one day and 3 for several.
    public static func allDayLines(busiest: Int, days: Int) -> Int { min(max(busiest, 1), days == 1 ? 6 : 3) }
}

// MARK: - Month rows

extension CalendarLogic {
    /// How many task lines a month cell `height` points tall has room for.
    public static func cellLines(height: CGFloat) -> Int {
        max(0, Int(((height - CalendarMetrics.cellHeader - 4) / (CalendarMetrics.chipHeight + CalendarMetrics.chipGap)).rounded(.down)))
    }

    /// What a week row of the month shows with room for `room` lines: the
    /// lines drawn, and per day how many items are left out ("+N", drawn on
    /// the line after the last). When everything fits, all of it shows; when
    /// not, one line is kept for the "+N".
    public static func monthRowFit(_ items: [WeekItem], room: Int, days: Int = 7) -> (lines: Int, hidden: [Int]) {
        let needed = (items.map(\.line).max() ?? -1) + 1
        if needed <= room { return (needed, Array(repeating: 0, count: days)) }
        let lines = max(room - 1, 0)
        return (lines, hiddenCounts(items, lines: lines, days: days))
    }
}

// MARK: - Days

extension CalendarLogic {
    /// Where the toolbar's + puts a task: today if it is on screen, else the
    /// anchor in the month, multi-week, year and agenda views, else the first
    /// day shown. On a phone it is always the anchor — the day picked in
    /// the small month (Flutter's FAB uses `calendarAnchorProvider`).
    public static func defaultNewDay(mode: CalendarMode, range: DayRange, anchor: Day, today: Day, compact: Bool = false) -> Day {
        if compact { return anchor }
        if range.contains(today) { return today }
        switch mode {
        case .month, .agenda, .year, .multiWeek: return anchor
        default: return range.start
        }
    }

    /// The days a mode shows (the multi-week view by the prefs' weeks).
    public static func calendarRange(_ prefs: CalendarPrefs, anchor: Day) -> DayRange {
        visibleRange(prefs.mode, anchor, weeks: prefs.weeks)
    }

    /// What a new task's sheet says it is for: 11月18日, 周三 / 今天, 周三 下午2:00.
    public static func newTaskHeading(date: Day, time: Int?, today: Day) -> String {
        let day = daySectionTitle(date, today: today)
        return time.map { "\(day) \(timeLabel($0))" } ?? day
    }

    /// A day's number in a month cell: 11月1日 on the first, the number otherwise.
    public static func cellDayLabel(_ d: Day) -> String { d.day == 1 ? "\(d.month)月1日" : "\(d.day)" }
}

// MARK: - Layout

extension CalendarLogic {
    /// The panel beside the calendar: the open task's detail (the batch
    /// panel is a little narrower).
    public static let sidePanelWidth: CGFloat = 360
    /// The least room the calendar itself needs next to that panel.
    public static let minCalendarWidth: CGFloat = 560

    /// Whether the calendar's column (`width` points) has room for a panel
    /// beside it: the wide layout of `calendar_screen.dart`. Narrower (its
    /// medium layout) the batch actions go along the bottom and a task's
    /// detail opens over the calendar.
    public static func panelsBeside(width: CGFloat) -> Bool { width >= minCalendarWidth + sidePanelWidth }
}
