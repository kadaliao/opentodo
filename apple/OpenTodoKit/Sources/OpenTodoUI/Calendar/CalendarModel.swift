// The calendar screen's state and its interface to the rest of the app.
//
//     let model = CalendarModel(prefs: storedPrefs, anchor: today)
//     CalendarView(model: model, tasks: tasks, lists: lists, now: now,
//                  actions: CalendarActions(move: repo.moveAll, …),
//                  options: CalendarOptions(taskTap: .card, quickAdd: { request, done in … }))
//     CalendarSidebar(model: model, tasks: tasks, lists: lists, now: now)   // in a sidebar column
//
// The caller owns the model: it reads `prefs` to store them (`calendar.prefs`
// in key_values) when they change, `picking` to show its batch panel, and
// sets `openTaskId` to the task open in its detail (highlighted on the
// calendar). Everything the person does to tasks comes back through
// `CalendarActions`; the calendar never writes anything itself.

import CoreGraphics
import OpenTodoDomain
import SwiftUI

/// The calendar's state: what it shows and what is picked, plus the
/// passing state of drags and the sheets it opens.
@Observable
public final class CalendarModel {
    /// Mode and display choices; handed to `savePrefs` when they change.
    public var prefs: CalendarPrefs {
        didSet { if prefs != oldValue { savePrefs?(prefs) } }
    }
    /// Stores the prefs (the app: `LocalSettings.setCalendarPrefs`).
    @ObservationIgnored public var savePrefs: ((CalendarPrefs) -> Void)?
    /// The task details pushed on a phone.
    public var phonePath: [String] = []
    /// The day the calendar is looking at (`calendarAnchorProvider`).
    public var anchor: Day
    /// The tasks picked at once (多选): the app's `model.selection`, set
    /// with `connect(selection:prefs:)`; a demo keeps its own.
    public private(set) var selection = SelectionModel()
    /// The task open in the caller's detail, drawn as selected.
    public var openTaskId: String?
    /// The 安排任务 panel is open.
    public var showsArrangePanel = false
    /// The new task being started (the quick-add slot is shown for it).
    public var newTask: CalendarNewTask?
    /// The task whose card is shown (`CalendarOptions.taskTap == .card`).
    public var cardTaskId: String?
    /// The entry the card points at (a span has one on each day).
    var cardAnchorKey: String?

    // Passing state, not part of the interface.
    var drag: CalendarDragSession?
    var hover: CalendarHover?
    var resize: (key: String, end: Int)?

    public init(prefs: CalendarPrefs = .standard, anchor: Day) {
        self.prefs = prefs
        self.anchor = anchor
    }

    /// A narrow screen (set by the view): week and multi-week aren't
    /// offered and fall back (`CalendarLogic.shownMode`).
    public var compact = false

    /// The days on screen.
    public var range: DayRange { visibleRange(mode, anchor, weeks: prefs.weeks) }

    /// The mode shown; setting it stores it.
    public var mode: CalendarMode {
        get { CalendarLogic.shownMode(prefs.mode, compact: compact) }
        set { prefs.mode = newValue }
    }

    /// Carries out a command from the keyboard, the toolbar or a menu.
    /// `order` is the page's tasks in the order shown (for ⌘A).
    public func perform(_ command: CalendarCommand, today: Day, order: [String] = []) {
        switch command {
        case .mode(let m): prefs.mode = m
        case .today: anchor = today
        case .page(let n): anchor = shiftAnchor(mode, anchor, n, weeks: prefs.weeks)
        case .selectAll: selection.selectAll(order)
        case .clearPicking: selection.clear()
        }
    }

    /// Hands the calendar the app's selection and the stored prefs, once
    /// (later calls do nothing, so a mode set by a route stays).
    public func connect(selection: SelectionModel, prefs: CalendarPrefs, today: Day? = nil,
                        save: ((CalendarPrefs) -> Void)? = nil) {
        guard !connected else { return }
        connected = true
        self.selection = selection
        self.prefs = prefs
        if let today { anchor = today }
        savePrefs = save
    }

    @ObservationIgnored private var connected = false

    /// Opens the day view of `date` (a day's heading, "+N", the year view).
    public func showDay(_ date: Day) {
        anchor = date
        prefs.mode = .day
    }
}

/// A new task the person started on the calendar: where, and when.
public struct CalendarNewTask: Identifiable, Hashable, Sendable {
    public let date: Day
    /// Minutes after midnight; nil for all day.
    public let time: Int?
    /// Where it was started, to point the popover at.
    let place: Place

    enum Place: Hashable, Sendable {
        case toolbar
        case cell(Day)
        case grid(Day, Int)
    }

    public init(date: Day, time: Int?) {
        self.date = date
        self.time = time
        place = .toolbar
    }

    init(date: Day, time: Int?, place: Place) {
        self.date = date
        self.time = time
        self.place = place
    }

    public var id: String { "\(date.key)@\(time.map(String.init) ?? "all")/\(place)" }
}

/// What the calendar asks of the app. Each is called on the main actor;
/// the defaults do nothing.
public struct CalendarActions {
    /// Show a task's detail (a click, or 打开详情 on its card).
    public var openTask: (String) -> Void
    /// Tasks dragged to other days or times: write them (`TaskRepo.moveAll`).
    public var move: ([CalendarMove]) -> Void
    /// A task's bottom edge dragged: its new duration in minutes.
    public var setDuration: (_ taskId: String, _ minutes: Int) -> Void
    /// Ticked or unticked.
    public var setDone: (_ taskId: String, _ done: Bool) -> Void
    /// A new task started with no `CalendarOptions.quickAdd` slot to type it in.
    public var newTask: (CalendarNewTask) -> Void

    public init(
        openTask: @escaping (String) -> Void = { _ in },
        move: @escaping ([CalendarMove]) -> Void = { _ in },
        setDuration: @escaping (String, Int) -> Void = { _, _ in },
        setDone: @escaping (String, Bool) -> Void = { _, _ in },
        newTask: @escaping (CalendarNewTask) -> Void = { _ in }
    ) {
        self.openTask = openTask
        self.move = move
        self.setDuration = setDuration
        self.setDone = setDone
        self.newTask = newTask
    }
}

/// How the calendar behaves, as the caller chooses.
public struct CalendarOptions {
    public enum TaskTap: Sendable {
        /// `CalendarActions.openTask` (a detail beside the calendar).
        case open
        /// A card over the calendar (a popover on a Mac, a half sheet on a
        /// phone) with 完成 and 打开详情.
        case card
    }

    /// Nil: as the person chose in 更多 (`CalendarPrefs.taskCard`).
    public var taskTap: TaskTap?
    /// The quick-add field for a new task, shown under a heading saying
    /// when (in a popover where it was started on a Mac, a sheet on a
    /// phone). Call `done` once it is added or given up. Nil: the
    /// calendar calls `CalendarActions.newTask` instead.
    public var quickAdd: ((CalendarNewTask, _ done: @escaping () -> Void) -> AnyView)?
    /// The task's own menu items (right-click, or a long press on a
    /// phone); the calendar adds 多选 to them.
    public var taskMenu: ((TodoTask) -> AnyView)?
    /// The toolbar offers the display choices and the lists to show (when
    /// no `CalendarSidebar` is beside it, as on a phone).
    public var filtersInToolbar: Bool

    public init(
        taskTap: TaskTap? = nil,
        quickAdd: ((CalendarNewTask, _ done: @escaping () -> Void) -> AnyView)? = nil,
        taskMenu: ((TodoTask) -> AnyView)? = nil,
        filtersInToolbar: Bool = true
    ) {
        self.taskTap = taskTap
        self.quickAdd = quickAdd
        self.taskMenu = taskMenu
        self.filtersInToolbar = filtersInToolbar
    }
}

// MARK: - Drags

/// A drag under way: the entry under the pointer and the picked tasks it
/// takes along, or a task from the 安排任务 panel.
struct CalendarDragSession {
    enum Item {
        case entry(CalendarEntry, others: [TodoTask])
        case unscheduled(TodoTask)
    }

    let item: Item
    /// Where the pointer was when the drag began, in the coordinate space of
    /// the view it began in (`origin`); filled in by the first drop target
    /// that sees the drag over it.
    var start: CGPoint?
    var origin: String?

    var count: Int {
        if case .entry(_, let others) = item { others.count + 1 } else { 1 }
    }

    var lead: CalendarEntry? {
        if case .entry(let e, _) = item { e } else { nil }
    }

    /// Whether `taskId` goes with the drag (to dim it while it does).
    func has(_ taskId: String) -> Bool {
        switch item {
        case .entry(let e, let others): e.task.id == taskId || others.contains { $0.id == taskId }
        case .unscheduled(let t): t.id == taskId
        }
    }

    /// Where everything goes when dropped on `day` (at `minute`, or into
    /// the all-day row).
    func moves(to day: Day, minute: Int? = nil, allDay: Bool = false) -> [CalendarMove] {
        switch item {
        case .entry(let e, let others):
            return dropTargets(e, others, day, minute: minute, allDay: allDay)
        case .unscheduled(let t):
            return [scheduleTarget(t, day, minute: allDay ? nil : minute)]
        }
    }

    /// The drag text: identifies a calendar drag to the drop targets (the
    /// real data stays in the model).
    static let marker = "opentodo-calendar-drag"
}

/// Where a drag hovers: a day of the month, the all-day row, or a minute on
/// the hour grid.
struct CalendarHover: Equatable {
    enum Target: Equatable {
        case cell(Day)
        case allDay(Day)
        case grid(Day, minute: Int, length: Int)
    }

    let target: Target
    let count: Int
}

extension CalendarModel {
    /// Begins dragging `entry` (with the picked tasks when it is one).
    func beginDrag(_ entry: CalendarEntry, others: [TodoTask]) {
        drag = CalendarDragSession(item: .entry(entry, others: others))
        hover = nil
    }

    func beginDrag(unscheduled task: TodoTask) {
        drag = CalendarDragSession(item: .unscheduled(task))
        hover = nil
    }

    /// Notes where the pointer is during the drag, in `space`; the first
    /// place seen is where it began.
    func dragSeen(at point: CGPoint, in space: String) {
        guard var d = drag, d.start == nil else { return }
        d.start = point
        d.origin = space
        drag = d
    }

    /// Whether a drop at `point` in `space` is where the drag began.
    func dropIsInPlace(_ point: CGPoint, in space: String) -> Bool {
        guard let d = drag, let start = d.start, d.origin == space else { return false }
        return CalendarLogic.droppedInPlace(start, point)
    }

    func openCard(_ taskId: String, at entryKey: String) {
        cardTaskId = taskId
        cardAnchorKey = entryKey
    }

    func closeCard() {
        cardTaskId = nil
        cardAnchorKey = nil
    }

    func endDrag() {
        drag = nil
        hover = nil
    }
}
