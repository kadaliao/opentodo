// The tasks module's timeline layout: the `TimelineView` component on the
// window's data. Clicks open or pick (`model.selection`), the menu is the
// task module's own (`TaskMenu`), changes go to TaskRepo
// (`applyTimelineEdit`), options are `LocalSettings.timelinePrefs`, and a
// click on an empty day asks for a new task there, with the lane's list,
// section, tag or priority.

import OpenTodoData
import OpenTodoDomain
import SwiftUI

struct TaskTimeline: View {
    @Environment(\.uiScale) private var s
    @Environment(AppModel.self) private var model
    var view: ViewRef

    /// A task being added by a click on a day.
    @State private var adding: TimelineNewTaskRequest?

    var body: some View {
        VStack(spacing: 0) {
            // As the Flutter pane: the quick-add field heads the timeline
            // on wide layouts too (⌘N / 新建任务 focus it).
            if model.width == .regular && canQuickAdd(view) {
                QuickAddField(focusRequests: model.taskList.quickAddRequests)
                    .padding(.horizontal, 16 * s)
                    .padding(.vertical, 8 * s)
                Divider()
            }
            timeline
        }
        .sheet(item: $adding) { TimelineNewTaskSheet(request: $0) }
        .selectAllTasksShortcut { model.timelineOrder(view) }
    }

    private var timeline: some View {
        TimelineView(
            timeline: model.timeline(for: view),
            view: view,
            now: model.now,
            selectedTaskId: model.selectedTaskId,
            prefs: Binding(get: { model.settings.timelinePrefs }, set: { model.settings.setTimelinePrefs($0) }),
            selection: model.selection.picked,
            onTap: { id, modifiers, order in model.tapOnTimeline(id, modifiers: modifiers, order: order) },
            onSetDone: { task, done in model.run { await model.setDone(task, done) } },
            onEdit: { edit in model.run { await model.applyTimelineEdit(edit) } },
            onNewTask: { day, lane in
                adding = TimelineNewTaskRequest(day: day, target: model.timelineNewTask(in: view, on: day, lane: lane))
            }
        ) { task in
            TaskMenu(task: task)
        }
        // Each view starts at its own today — worked out again once the
        // data is in (today's start shows its earliest overdue task).
        .id(TimelineIdentity(view: view, loaded: model.loaded))
    }
}

private struct TimelineIdentity: Hashable {
    var view: ViewRef
    var loaded: Bool
}

struct TimelineNewTaskRequest: Identifiable {
    let id = UUID()
    var day: Day
    var target: QuickAddTarget
}

/// 新建任务 on a day of the timeline: the quick-add field (dates and the
/// rest still understood), the task going into the lane it was asked from.
struct TimelineNewTaskSheet: View {
    @Environment(\.uiScale) private var s
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var request: TimelineNewTaskRequest
    /// The list picked in the sheet; nil keeps the lane's (Flutter's
    /// `_listId`: another list drops the lane's section).
    @State private var pickedList: String?

    private var target: QuickAddTarget {
        var t = request.target
        if let pickedList, pickedList != t.listId {
            t.listId = pickedList
            t.sectionId = nil
        }
        return t
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12 * s) {
                QuickAddField(target: target, prompt: "在\(dateLabel(request.day, today: model.today))添加任务",
                              focusRequests: 1) { id in
                    if model.width == .regular { model.selectedTaskId = id }
                    dismiss()
                }
                Text(summary)
                    .uiFont(.footnote)
                    .foregroundStyle(.secondary)
                Picker(selection: Binding(get: { target.listId }, set: { pickedList = $0 })) {
                    Label("收集箱", systemImage: "tray").tag(inboxListId)
                    ForEach(model.lists) { l in
                        listMenuLabel(l, fallback: nil).tag(l.id)
                    }
                } label: {
                    Label("清单", systemImage: "list.bullet")
                }
                .fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20 * s)
            .padding(.top, 8 * s)
            .navigationTitle("新建任务")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 440 * s, height: 180 * s)
        #else
        .presentationDetents([.height(230)])
        #endif
    }

    /// 11月27日 · 工作 · 进行中 · #会 · 高优先级
    private var summary: String {
        let t = target
        var parts = ["\(request.day.month)月\(request.day.day)日", listName(t.listId, model.listsById)]
        if let s = t.sectionId, let section = model.sectionsByList[t.listId]?.first(where: { $0.id == s }) {
            parts.append(section.name)
        }
        parts += t.tags.map { "#\($0)" }
        if let p = t.priority, p != .none { parts.append(priorityName(p)) }
        return parts.joined(separator: " · ")
    }
}

/// `-OTOpen timeline:<view route>` (`timeline:list:work`,
/// `timeline:smart:today` …): that view, as a timeline.
struct TimelineDebugPresenter: ViewModifier {
    @Environment(AppModel.self) private var model
    var route: DebugRoute?

    func body(content: Content) -> some View {
        content.task {
            guard case .timelineView(let text)? = route, let inner = DebugRoute(text),
                  let view = TimelineDebugPresenter.view(of: inner) else { return }
            model.settings.setLayout(view, .timeline)
            model.applyWhenLoaded(inner)
        }
    }

    /// The view a route opens, if it opens one.
    static func view(of route: DebugRoute) -> ViewRef? {
        switch route {
        case .smart(let k): SmartKind(rawValue: k).map(ViewRef.smart)
        case .list(let id): id == inboxListId ? .smart(.inbox) : .list(id)
        case .tag(let t): .tag(t)
        case .filter(let id): .filter(id)
        default: nil
        }
    }
}
