// The calendar module. Wide (macOS, iPad): a split view with the
// calendar's sidebar (module bar on top on macOS, small month, lists to
// show, 显示已完成 / 农历) and the calendar; beside it the open task's
// detail, or the batch panel while tasks are picked. Compact (iPhone): the
// calendar in a navigation stack, a task's detail pushed on it, the batch
// actions in the bottom bar. The calendar itself is `Calendar/`; its
// callbacks go to the database through `CalendarWiring.swift`.

import OpenTodoDomain
import SwiftUI

struct CalendarScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.width == .compact {
                PhoneCalendar()
            } else {
                CalendarSplitView()
            }
        }
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

    var body: some View {
        CalendarView(
            model: model.calendar, tasks: model.data.tasks, lists: model.lists, filters: model.filters,
            now: model.now, actions: model.calendarActions,
            options: CalendarOptions(
                quickAdd: { request, done in AnyView(CalendarQuickAdd(request: request, done: done)) },
                taskMenu: { task in AnyView(TaskMenu(task: task)) },
                filtersInToolbar: model.width == .compact
            )
        )
    }
}

private struct CalendarSplitView: View {
    @Environment(\.uiScale) private var s
    @Environment(AppModel.self) private var model
    /// Room for the detail or batch panel beside the calendar; narrower,
    /// the batch bar goes along the bottom and a task opens in a sheet.
    @State private var beside = true

    var body: some View {
        let calendar = model.calendar
        NavigationSplitView {
            CalendarSidebar(model: calendar, tasks: calendar.shownTasks(model.data.tasks, filters: model.filters, now: model.now), lists: model.lists, now: model.now)
                .moduleBar()
                .modifier(AccountFooter())
                .navigationSplitViewColumnWidth(min: 220, ideal: 250 * s, max: 320 * s)
                #if os(iOS)
                .navigationTitle("日历")
                #endif
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    CalendarArea()
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
}

/// The open task beside the calendar, under a 任务详情 heading with a close
/// button.
private struct CalendarDetailPane: View {
    @Environment(\.uiScale) private var s
    @Environment(AppModel.self) private var model
    let taskId: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("任务详情").uiFont(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.calendar.openTaskId = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 14 * s)
            .padding(.vertical, 8 * s)
            TaskDetailView(taskId: taskId)
        }
    }
}

private struct PhoneCalendar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var calendar = model.calendar
        NavigationStack(path: $calendar.phonePath) {
            CalendarArea()
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
