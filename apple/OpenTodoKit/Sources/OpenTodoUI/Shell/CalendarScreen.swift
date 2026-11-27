// The calendar module in the window. macOS: `CalendarPane` in the window's
// detail column — the calendar, and beside it the open task's detail or
// the batch panel while tasks are picked; the lists to show are in the
// toolbar's 更多 and the small month sits at the foot of the window's one
// sidebar (Shell/MacShell.swift). iPad: the same pane in a split view of
// its own with the calendar's sidebar (small month, lists to show, 显示已完成
// / 农历). Compact (iPhone): the calendar in a navigation stack, a task's
// detail pushed on it, the batch actions in the bottom bar. The calendar
// itself is `Calendar/`; its callbacks go to the database through
// `CalendarWiring.swift`.

import OpenTodoDomain
import SwiftUI

/// The calendar as a tab (iOS, iPadOS).
struct CalendarScreen: View {
    @Environment(\.uiScale) private var s
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.width == .compact {
                PhoneCalendar()
            } else {
                let calendar = model.calendar
                NavigationSplitView {
                    CalendarSidebar(model: calendar, tasks: calendar.shownTasks(model.data.tasks, filters: model.filters, now: model.now), lists: model.lists, now: model.now)
                        .navigationSplitViewColumnWidth(min: 220, ideal: 250 * s, max: 320 * s)
                        #if os(iOS)
                        .navigationTitle("日历")
                        #endif
                } detail: {
                    CalendarPane(listsInToolbar: false)
                }
            }
        }
        .modifier(CalendarConnection())
    }
}

/// Wires the calendar to the window's data when it comes on screen.
struct CalendarConnection: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .onAppear {
                model.connectCalendar()
                // Back from another module: what was open may be gone or hidden.
                model.closeCalendarTaskIfGone(hidden: true)
            }
            .onChange(of: model.data) { model.closeCalendarTaskIfGone() }
    }
}

/// The calendar view on the window's data.
private struct CalendarArea: View {
    @Environment(AppModel.self) private var model
    /// No sidebar of the calendar's own beside it: the lists to show go in
    /// the toolbar's 更多.
    var listsInToolbar: Bool

    var body: some View {
        CalendarView(
            model: model.calendar, tasks: model.data.tasks, lists: model.lists, filters: model.filters,
            now: model.now, actions: model.calendarActions,
            options: CalendarOptions(
                quickAdd: { request, done in AnyView(CalendarQuickAdd(request: request, done: done)) },
                taskMenu: { task in AnyView(TaskMenu(task: task)) },
                filtersInToolbar: listsInToolbar
            )
        )
    }
}

/// The calendar with the open task's detail (or the batch panel) beside
/// it: what fills a detail column.
struct CalendarPane: View {
    @Environment(\.uiScale) private var s
    @Environment(AppModel.self) private var model
    var listsInToolbar: Bool
    /// Room for the detail or batch panel beside the calendar; narrower,
    /// the batch bar goes along the bottom and a task opens in a sheet.
    @State private var beside = true

    var body: some View {
        let calendar = model.calendar
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                CalendarArea(listsInToolbar: listsInToolbar)
                    #if os(iOS)
                    .batchBottomBar(
                        selection: model.selection.isActive && !beside
                            ? BatchSelection(ids: model.selection.ids, tasks: model.data.tasks) : nil,
                        lists: model.lists, knownTags: model.tags, today: model.today
                    ) { action in
                        model.run { await model.applyBatch(action, order: model.calendarOrder) }
                    }
                    #endif
                #if os(macOS)
                if model.selection.isActive && !beside {
                    BatchBar(
                        selection: BatchSelection(ids: model.selection.ids, tasks: model.data.tasks),
                        lists: model.lists, knownTags: model.tags, today: model.today
                    ) { action in
                        model.run { await model.applyBatch(action, order: model.calendarOrder) }
                    }
                }
                #endif
            }
            if beside && model.selection.isActive {
                Divider()
                BatchPanel(
                    selection: BatchSelection(ids: model.selection.ids, tasks: model.data.tasks),
                    lists: model.lists, knownTags: model.tags, today: model.today
                ) { action in
                    model.run { await model.applyBatch(action, order: model.calendarOrder) }
                }
                .frame(width: 340 * s)
            } else if beside, let id = calendar.openTaskId, model.task(id) != nil {
                Divider()
                CalendarDetailPane(taskId: id)
                    .frame(width: CalendarLogic.sidePanelWidth * s)
            }
        }
        .onGeometryChange(for: Bool.self) { [s] in CalendarLogic.panelsBeside(width: $0.size.width, scale: s) } action: { beside = $0 }
        .sheet(item: Binding(
            get: { beside ? nil : calendar.openTaskId.flatMap { model.task($0) != nil ? OpenTask(id: $0) : nil } },
            set: { if $0 == nil { calendar.openTaskId = nil } }
        )) { open in
            CalendarDetailSheet(taskId: open.id)
        }
    }
}

/// The open task beside the calendar; its title row has 更多 and the
/// close button.
private struct CalendarDetailPane: View {
    @Environment(AppModel.self) private var model
    let taskId: String

    var body: some View {
        TaskDetailView(taskId: taskId)
            .environment(\.taskDetailChrome, TaskDetailChrome(onClose: { model.calendar.openTaskId = nil }))
    }
}

private struct PhoneCalendar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var calendar = model.calendar
        NavigationStack(path: $calendar.phonePath) {
            CalendarArea(listsInToolbar: true)
                .navigationDestination(for: String.self) { id in
                    TaskDetailView(taskId: id)
                }
                #if os(iOS)
                .batchBottomBar(
                    selection: model.selection.isActive
                        ? BatchSelection(ids: model.selection.ids, tasks: model.data.tasks) : nil,
                    lists: model.lists, knownTags: model.tags, today: model.today
                ) { action in
                    model.run { await model.applyBatch(action, order: model.calendarOrder) }
                }
                #endif
        }
    }
}

private struct OpenTask: Identifiable {
    let id: String
}

/// A task's detail over the calendar when the window has no room beside
/// it (the Flutter version pushes the detail page there).
private struct CalendarDetailSheet: View {
    @Environment(\.uiScale) private var s
    @Environment(AppModel.self) private var model
    let taskId: String

    var body: some View {
        NavigationStack {
            TaskDetailView(taskId: taskId)
                .navigationTitle("任务详情")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { model.calendar.openTaskId = nil }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 420 * s, idealWidth: 460 * s, minHeight: 520 * s, idealHeight: 620 * s)
        #endif
    }
}
