// Small pieces the calendar views use besides the shared `Components/`
// (`PriorityCheckbox`, `Palette`): the lunar note beside a day's number, the
// "+N" of a full cell, the day number, and the context (data, callbacks,
// options) handed down from `CalendarView`.

import OpenTodoDomain
import SwiftUI

// MARK: - Colours

/// 休 and 班 beside a day's number, as the system calendar marks them.
/// (Everything else uses `Palette`.)
enum DayMarkColors {
    static let off = Color.green
    static let worked = Color.red
}

// MARK: - Context

/// What `CalendarView` hands down to the view of each mode: the data, the
/// day's entries, the callbacks and the options. Built once per render.
struct CalendarContext {
    let model: CalendarModel
    let tasks: [TodoTask]
    let lists: [String: TaskList]
    /// The saved filters, for 更多 › 过滤器 and `CalendarPrefs.filterId`.
    let filters: [TaskFilter]
    let now: LocalDateTime
    let actions: CalendarActions
    let options: CalendarOptions
    let compact: Bool

    var today: Day { now.day }

    /// The tasks the calendar shows: all of them, or those of the filter
    /// chosen in 更多 (a filter since deleted counts as none).
    var shownTasks: [TodoTask] { model.shownTasks(tasks, filters: filters, now: now) }

    func entries(_ range: DayRange) -> [CalendarEntry] {
        calendarEntries(shownTasks, range, today: today, filter: model.prefs.filter)
    }

    /// What a click on a task does: the caller's choice, else the person's.
    var taskTap: CalendarOptions.TaskTap {
        options.taskTap ?? (model.prefs.taskCard ? .card : .open)
    }

    func color(of task: TodoTask) -> Color {
        task.listId == inboxListId ? Palette.accent : Palette.list(lists[task.listId]?.color)
    }

    func listName(_ id: String) -> String {
        id == inboxListId ? "收集箱" : (lists[id]?.name ?? "收集箱")
    }

    /// The picked tasks, or else the one open in the detail.
    func isSelected(_ e: CalendarEntry) -> Bool {
        guard !e.projected else { return false }
        return model.selection.isActive ? model.selection.contains(e.task.id) : model.openTaskId == e.task.id
    }

    /// The picked tasks a drag of `lead` takes along, when it is one of them.
    func dragAlong(_ lead: CalendarEntry) -> [TodoTask] {
        let picked = calendarPicked(tasks, ids: model.selection.ids)
        guard picked.count > 1, picked.contains(where: { $0.id == lead.task.id }) else { return [] }
        return picked.filter { $0.id != lead.task.id }
    }
}

// MARK: - Day notes

/// Beside a day's number: its lunar day or festival, and 休 or 班.
struct CalendarDayNote: View {
    let date: Day
    var dim = false
    /// The text's style; nil: 10 points.
    var style: Font.TextStyle?
    @Environment(\.uiScale) private var s

    var body: some View {
        let note = dayNote(date)
        HStack(spacing: 3 * s) {
            Text(note.label)
                .font(style.map { Font.ui($0, scale: s) } ?? Font.ui(size: 10, scale: s))
                .foregroundStyle(dim ? AnyShapeStyle(.quaternary) : note.special ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
            if let off = note.off {
                Text(off ? "休" : "班")
                    .uiFont(size: 9, weight: .semibold)
                    .foregroundStyle(off ? DayMarkColors.off : DayMarkColors.worked)
                    .padding(.horizontal, 2 * s)
                    .background((off ? DayMarkColors.off : DayMarkColors.worked).opacity(dim ? 0.06 : 0.14),
                                in: RoundedRectangle(cornerRadius: 3))
                    .opacity(dim ? 0.5 : 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "+N": more tasks than a day has room for. Opens the day.
struct CalendarMoreButton: View {
    let count: Int
    let action: () -> Void
    @Environment(\.uiScale) private var s

    var body: some View {
        Button(action: action) {
            Text(verbatim: "+\(count)")
                .uiFont(size: 11, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4 * s)
                .frame(height: CalendarMetrics.chipHeight * s)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("还有\(count)项")
    }
}

/// The number of a day in a round mark: filled with the accent for today.
struct CalendarDayNumber: View {
    let text: String
    let isToday: Bool
    var dim = false
    /// At 标准.
    var size: CGFloat = 12
    @Environment(\.uiScale) private var s

    var body: some View {
        Text(text)
            .uiFont(size: size, weight: isToday ? .semibold : .regular)
            .monospacedDigit()
            .foregroundStyle(isToday ? AnyShapeStyle(Color.white) : dim ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, (isToday ? 6 : 4) * s)
            .frame(minWidth: (size + 10) * s, minHeight: (size + 8) * s)
            .background {
                if isToday { Capsule().fill(Color.red) }
            }
    }
}

// MARK: - Platform

/// The keys held down right now (macOS); a touch screen has none.
@MainActor
func currentClickModifiers() -> TapModifiers {
    #if os(macOS)
    let flags = NSEvent.modifierFlags
    var m: TapModifiers = []
    if flags.contains(.command) { m.insert(.command) }
    if flags.contains(.shift) { m.insert(.shift) }
    return m
    #else
    return []
    #endif
}

/// Taps pick while picking, and a long press drags: a touch screen.
var calendarIsTouch: Bool {
    #if os(iOS)
    true
    #else
    false
    #endif
}

// MARK: - Starting a task

extension CalendarContext {
    /// A click on an empty part of a day: stops picking while tasks are
    /// picked, otherwise starts a task there.
    func tapEmpty(_ day: Day, time: Int?, place: CalendarNewTask.Place) {
        // While picking, a click on an empty day stops picking rather than
        // starting a task.
        if model.selection.isActive || model.selection.isPicking {
            model.selection.clear()
            return
        }
        startNewTask(CalendarNewTask(date: day, time: time, place: place))
    }

    /// Shows the quick-add slot for `request`, or hands it to the app.
    func startNewTask(_ request: CalendarNewTask) {
        if options.quickAdd != nil {
            model.newTask = request
        } else {
            actions.newTask(request)
        }
    }
}

/// The heading and the caller's quick-add field for a new task.
struct NewTaskPanel: View {
    let ctx: CalendarContext
    let request: CalendarNewTask
    @Environment(\.uiScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * s) {
            Label(CalendarLogic.newTaskHeading(date: request.date, time: request.time, today: ctx.today), systemImage: "calendar.badge.plus")
                .uiFont(.headline)
                .foregroundStyle(Palette.accent)
            if let field = ctx.options.quickAdd {
                field(request) { ctx.model.newTask = nil }
            }
        }
        .padding(16 * s)
        .frame(minWidth: 320 * s, idealWidth: 380 * s, alignment: .leading)
    }
}

extension View {
    /// The popover of a new task started at `place` (not on a phone, which
    /// uses a sheet), pointing at `anchor` within this view.
    func calendarNewTaskPopover(_ ctx: CalendarContext, place: CalendarNewTask.Place, anchor: CGRect? = nil) -> some View {
        popover(
            isPresented: Binding(
                get: { !ctx.compact && ctx.model.newTask?.place == place },
                set: { if !$0, ctx.model.newTask?.place == place { ctx.model.newTask = nil } }
            ),
            attachmentAnchor: anchor.map { .rect(.rect($0)) } ?? .rect(.bounds),
            arrowEdge: .trailing
        ) {
            if let request = ctx.model.newTask { NewTaskPanel(ctx: ctx, request: request) }
        }
    }

    /// The card of a task clicked at `entryKey` (not on a phone, which uses
    /// a sheet).
    func calendarCardPopover(_ ctx: CalendarContext, entryKey: String) -> some View {
        popover(
            isPresented: Binding(
                get: { !ctx.compact && ctx.model.cardTaskId != nil && ctx.model.cardAnchorKey == entryKey },
                set: { if !$0, ctx.model.cardAnchorKey == entryKey { ctx.model.closeCard() } }
            ),
            arrowEdge: .trailing
        ) {
            if let id = ctx.model.cardTaskId, let task = ctx.tasks.first(where: { $0.id == id }) {
                TaskCard(task: task, ctx: ctx)
            }
        }
    }
}
