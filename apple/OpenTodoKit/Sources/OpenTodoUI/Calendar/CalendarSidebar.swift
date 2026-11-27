// Beside the calendar: a small month to jump to a day, which lists to show
// and what else to show (`CalendarPrefs`), for a sidebar column; the same
// choices as a menu for the toolbar; and the 安排任务 panel of tasks without
// a date, to drag onto the calendar. Port of `calendar_screen.dart`'s
// `CalendarSidebar` and `ListFilter`; the panel is new.

import OpenTodoDomain
import SwiftUI

/// The calendar's sidebar: put it in the sidebar column next to a
/// `CalendarView` on the same model.
public struct CalendarSidebar: View {
    let model: CalendarModel
    let tasks: [TodoTask]
    let lists: [TaskList]
    let now: LocalDateTime

    public init(model: CalendarModel, tasks: [TodoTask], lists: [TaskList], now: LocalDateTime) {
        self.model = model
        self.tasks = tasks
        self.lists = lists
        self.now = now
    }

    public var body: some View {
        List {
            Section {
                CalendarMonthJumper(model: model, tasks: tasks, now: now)
            }
            Section {
                CalendarListToggles(model: model, lists: lists)
            } header: {
                Text("显示的清单").uiDefaultFont(.subheadline, weight: .semibold)
            }
            Section {
                CalendarDisplayToggles(model: model)
            } header: {
                Text("显示").uiDefaultFont(.subheadline, weight: .semibold)
            }
        }
        .listStyle(.sidebar)
    }
}

/// A small month to jump to a day: the month's name with ‹ ○ › to page it
/// (○ is today), a dot under the days with something on. In the calendar's
/// sidebar, and on macOS at the foot of the window's sidebar while the
/// calendar is on screen.
public struct CalendarMonthJumper: View {
    @Environment(\.uiScale) private var s
    let model: CalendarModel
    /// The tasks the calendar shows (`CalendarModel.shownTasks`).
    let tasks: [TodoTask]
    let now: LocalDateTime
    var rowHeight: CGFloat = 30

    /// Months the small month is paged away from the calendar's.
    @State private var monthOffset = 0

    public init(model: CalendarModel, tasks: [TodoTask], now: LocalDateTime, rowHeight: CGFloat = 30) {
        self.model = model
        self.tasks = tasks
        self.now = now
        self.rowHeight = rowHeight
    }

    public var body: some View {
        let shown = model.anchor.startOfMonth.addingMonths(monthOffset)
        let marked = Set(entriesByDay(
            calendarEntries(tasks, monthGrid(shown.year, shown.month), today: now.day, filter: model.prefs.filter)
        ).keys)
        VStack(spacing: 4 * s) {
            HStack {
                Text(verbatim: "\(shown.year)年\(shown.month)月").uiFont(.headline)
                Spacer()
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("上个月")
                    .help("上个月")
                Button { monthOffset = 0; model.anchor = now.day } label: { Image(systemName: "circle") }
                    .accessibilityLabel("今天")
                    .help("今天")
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("下个月")
                    .help("下个月")
            }
            .buttonStyle(.borderless)
            .imageScale(.small)
            MiniMonth(year: shown.year, month: shown.month, selected: model.anchor, today: now.day,
                      marks: .dots(marked), rowHeight: rowHeight, fontSize: 12) { day in
                monthOffset = 0
                model.anchor = day
            }
        }
        .padding(.vertical, 4 * s)
        .onChange(of: model.anchor) { monthOffset = 0 }
    }
}

/// A tick for each list: shown on the calendar or not.
struct CalendarListToggles: View {
    let model: CalendarModel
    let lists: [TaskList]

    var body: some View {
        let rows = [(inboxListId, "收集箱", Optional<Int>.none)] + lists.map { ($0.id, $0.name, $0.color) }
        ForEach(rows, id: \.0) { id, name, color in
            Toggle(isOn: Binding(
                get: { !model.prefs.hiddenLists.contains(id) },
                set: { show in
                    if show { model.prefs.hiddenLists.remove(id) } else { model.prefs.hiddenLists.insert(id) }
                }
            )) {
                Label {
                    Text(name).lineLimit(1)
                } icon: {
                    Image(systemName: id == inboxListId ? "tray" : "list.bullet")
                        .foregroundStyle(id == inboxListId ? Palette.accent : Palette.list(color))
                }
            }
            #if os(macOS)
            .toggleStyle(.checkbox)
            #endif
        }
    }
}

/// 显示已完成, 显示重复任务以后的日期, 显示农历和节假日.
struct CalendarDisplayToggles: View {
    let model: CalendarModel

    var body: some View {
        @Bindable var model = model
        Toggle("显示已完成", isOn: $model.prefs.showCompleted)
        Toggle("显示重复任务以后的日期", isOn: $model.prefs.showRepeats)
        Toggle("显示农历和节假日", isOn: $model.prefs.showLunar)
    }
}

// MARK: - 安排任务

/// Tasks without a date, by list, to drag onto the calendar (on a phone, a
/// tap puts one on the day selected). New in the Swift version.
struct ArrangePanel: View {
    @Environment(\.uiScale) private var s
    let ctx: CalendarContext

    /// The list shown; nil for all.
    @State private var listId: String?

    var body: some View {
        let tasks = unscheduledTasks(ctx.tasks, listId: listId)
        VStack(spacing: 0) {
            Picker("清单", selection: $listId) {
                Text("所有清单").tag(String?.none)
                Divider()
                Text("收集箱").tag(String?.some(inboxListId))
                ForEach(ctx.lists.values.sorted { $0.sortOrder < $1.sortOrder }, id: \.id) { l in
                    Text(l.name).tag(String?.some(l.id))
                }
            }
            .labelsHidden()
            .padding(.horizontal, 12 * s)
            .padding(.vertical, 8 * s)
            if tasks.isEmpty {
                ContentUnavailableView("都排好了", systemImage: "checkmark.circle", description: Text("没有日期的任务会列在这里"))
            } else {
                List(tasks, id: \.id) { task in
                    row(task)
                }
                #if os(macOS)
                .listStyle(.inset)
                #endif
                Text(ctx.compact ? "点一下排到\(daySectionTitle(ctx.model.anchor, today: ctx.today))" : "拖到日历上安排日期")
                    .uiFont(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8 * s)
            }
        }
    }

    private func row(_ task: TodoTask) -> some View {
        HStack(spacing: 8 * s) {
            PriorityCheckbox(checked: false, priority: task.priority, size: 16) {
                ctx.actions.setDone(task.id, true)
            }
            Text(task.title.isEmpty ? "无标题" : task.title).lineLimit(1)
            Spacer(minLength: 4)
            Text(ctx.listName(task.listId)).uiFont(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if ctx.compact { ctx.actions.move([scheduleTarget(task, ctx.model.anchor)]) }
        }
        .onDrag {
            ctx.model.beginDrag(unscheduled: task)
            return NSItemProvider(object: CalendarDragSession.marker as NSString)
        }
    }
}

/// 过滤器: show only the tasks of a saved filter (新功能).
struct CalendarFilterPicker: View {
    let model: CalendarModel
    let filters: [TaskFilter]

    var body: some View {
        @Bindable var model = model
        Picker(selection: $model.prefs.filterId) {
            Text("全部任务").tag(String?.none)
            if !filters.isEmpty { Divider() }
            ForEach(filters.sorted { $0.sortOrder < $1.sortOrder }, id: \.id) { f in
                Text(f.name).tag(String?.some(f.id))
            }
        } label: {
            Label("过滤器", systemImage: "line.3.horizontal.decrease")
        }
    }
}
