// The Mac window: one sidebar for the whole app and, beside it, whatever
// is selected there.
//
// The sidebar (`ViewsList`) never changes with what is on screen: 搜索 on
// top; the smart lists; 日历, 四象限, 专注, 习惯, 倒数日 as rows of their
// own, named, with a word of news at the end (习惯 2/5, 专注中); the lists,
// filters and tags; the account at the foot. A view shows the tasks module
// (list and detail), a module row shows that module. The only thing that
// comes and goes is the small month above the account while the calendar
// is on screen (and the window is tall enough for it).
//
// It is one `NavigationSplitView` for every module, so the sidebar keeps
// its width, its scroll position and its selection when the right side
// changes. The tasks module therefore isn't a third column of the split
// view but a split of its own inside the detail column (`MacTasksSplit`):
// the list, and beside it the open task's detail — always there for a
// list, only while a task is open (or tasks are picked) beside a board or
// a timeline, which want the width. The divider between them drags.
//
// Why not the system's inspector for the detail: it never gives way. The
// list beside it can't be narrower than the inspector, and neither shrinks
// when the window does, so at 760 wide the three were laid out 990 wide
// and pushed out of the window on both sides.

#if os(macOS)
import OpenTodoDomain
import SwiftUI

struct MacShell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.uiScale) private var s

    var body: some View {
        NavigationSplitView {
            ViewsList(mode: .sidebar, modules: AppModule.sidebarModules)
                .modifier(SidebarSearch())
                .modifier(SidebarFooter())
                // Only the ideal width grows with 界面大小: at the window's
                // smallest (760, RootView) the sidebar, the list and the
                // detail must still fit side by side.
                .navigationSplitViewColumnWidth(min: 180, ideal: 230 * s, max: 320 * s)
        } detail: {
            switch model.module {
            case .tasks:
                MacTasksSplit()
            case .calendar:
                CalendarPane(listsInToolbar: true)
                    .modifier(CalendarConnection())
            case .matrix, .focus, .habits, .countdowns:
                EfficiencyScreen(module: model.module)
            }
        }
    }
}

extension AppModel {
    /// A task is open in the tasks module, or tasks are picked.
    var hasOpenTasks: Bool { selectedTaskId != nil || selection.isActive }

    func closeOpenTasks() {
        selectedTaskId = nil
        selection.clear()
    }
}

// MARK: - Tasks

/// How the list and the detail share the width beside the sidebar.
public enum TaskSplitLogic {
    /// The detail's width until the person drags the divider.
    nonisolated public static let defaultDetailWidth: CGFloat = 380
    /// Neither goes narrower than this while there's room for both …
    nonisolated public static let minListWidth: CGFloat = 280
    nonisolated public static let minDetailWidth: CGFloat = 280
    /// … and in the smallest window with a wide sidebar the detail gives
    /// way down to this before the list does.
    nonisolated public static let leastDetailWidth: CGFloat = 220
    nonisolated public static let maxDetailWidth: CGFloat = 560
    /// The divider between them (its line, and room to take hold of it).
    nonisolated public static let handleWidth: CGFloat = 9

    /// The detail's width in `total` points of room: what the person chose
    /// (`wanted`), within the limits, leaving the list its minimum.
    nonisolated public static func detailWidth(wanted: CGFloat, total: CGFloat) -> CGFloat {
        let room = total - minListWidth - handleWidth
        let chosen = min(max(wanted, minDetailWidth), maxDetailWidth)
        return max(leastDetailWidth, min(chosen, room))
    }
}

/// The tasks module beside the sidebar: the view's tasks, and the open
/// task's detail (or the batch panel) in a pane on the right.
private struct MacTasksSplit: View {
    @Environment(AppModel.self) private var model
    /// The detail's width as the person left it (every window's).
    @AppStorage("ot.taskDetailWidth") private var stored = Double(TaskSplitLogic.defaultDetailWidth)
    /// The room beside the sidebar.
    @State private var total: CGFloat = 950
    /// While the divider is dragged: the width it started from, and now.
    @State private var drag: (from: CGFloat, now: CGFloat)?

    var body: some View {
        let showing = !wantsWidth || model.hasOpenTasks
        let width = TaskSplitLogic.detailWidth(wanted: drag?.now ?? CGFloat(stored), total: total)
        HStack(spacing: 0) {
            TaskListArea(view: model.view)
                .frame(maxWidth: .infinity)
                // The list's toolbar buttons stop where the list does.
                .environment(\.toolbarTrailingInset, showing ? width + TaskSplitLogic.handleWidth : 0)
            if showing {
                handle(width)
                TaskPane(closable: wantsWidth)
                    .frame(width: width)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { total = $0 }
    }

    /// The view on screen is laid out as a board or a timeline.
    private var wantsWidth: Bool {
        model.prefs(for: model.view).layoutIn(model.view) != .list
    }

    /// The divider: a hairline to look at in nine points to take hold of.
    /// The nine are its own, between the list and the detail: laid over
    /// their edges instead they can't be clicked, the list's and the
    /// form's scroll views (AppKit's) take the mouse first. Dragging
    /// changes the detail's width; a double click puts it back.
    private func handle(_ width: CGFloat) -> some View {
        Color.clear
            .frame(width: TaskSplitLogic.handleWidth)
            .contentShape(Rectangle())
            .overlay {
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
                    .ignoresSafeArea(edges: .top)
            }
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { g in
                        let from = drag?.from ?? width
                        drag = (from, TaskSplitLogic.detailWidth(wanted: from - g.translation.width, total: total))
                    }
                    .onEnded { _ in
                        if let now = drag?.now { stored = Double(now) }
                        drag = nil
                    }
            )
            .onTapGesture(count: 2) { stored = Double(TaskSplitLogic.defaultDetailWidth) }
            // VoiceOver and keyboards resize it too.
            .accessibilityElement()
            .accessibilityLabel("详情宽度")
            .accessibilityValue("\(Int(width))")
            .accessibilityAdjustableAction { direction in
                let step: CGFloat = direction == .increment ? 20 : -20
                stored = Double(TaskSplitLogic.detailWidth(wanted: width + step, total: total))
            }
    }
}

/// Beside the tasks: the open task's detail, or the batch panel while
/// tasks are picked.
private struct TaskPane: View {
    @Environment(AppModel.self) private var model
    /// Beside a board or a timeline the detail can be put away (Flutter's
    /// 关闭详情).
    var closable: Bool

    var body: some View {
        content
            // The task's menu and 关闭 in the pane itself: the window's
            // toolbar is the list's.
            .environment(\.taskDetailChrome, chrome)
    }

    private var chrome: TaskDetailChrome {
        guard closable else { return TaskDetailChrome() }
        return TaskDetailChrome(onClose: { [model] in model.closeOpenTasks() })
    }

    @ViewBuilder private var content: some View {
        if model.selection.isActive {
            BatchDetail()
        } else if let id = model.selectedTaskId {
            TaskDetailView(taskId: id)
        } else {
            EmptyState.noTaskSelected
        }
    }
}

// MARK: - Sidebar

/// 搜索 at the top of the sidebar: looks like a search field, opens the
/// search panel over the window (⌘F), whatever module is on screen.
private struct SidebarSearch: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.uiScale) private var s

    func body(content: Content) -> some View {
        content.safeAreaBar(edge: .top, spacing: 0) {
            Button {
                model.requestSearch()
            } label: {
                HStack(spacing: 6 * s) {
                    Image(systemName: "magnifyingglass")
                    Text("搜索")
                    Spacer(minLength: 0)
                    Text("⌘F").foregroundStyle(.tertiary)
                }
                .uiFont(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9 * s)
                .frame(height: 28 * s)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("搜索任务、清单、标签（⌘F）")
            .accessibilityLabel("搜索")
            .padding(.horizontal, 10 * s)
            .padding(.top, 2 * s)
            .padding(.bottom, 8 * s)
        }
    }
}

/// The foot of the sidebar: the small month while the calendar is on
/// screen, and the account (data's `AccountSidebarItem`; a click opens 设置).
private struct SidebarFooter: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.uiScale) private var s
    /// The sidebar has the height for the small month and still a good
    /// part of its rows.
    @State private var tall = true

    func body(content: Content) -> some View {
        // Hard edge: with the soft one the rows under the bar show through
        // as blurred ghosts right behind the account's icon and name.
        content.safeAreaBar(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if model.module == .calendar && tall {
                    let calendar = model.calendar
                    Divider().padding(.horizontal, 12 * s)
                    CalendarMonthJumper(
                        model: calendar,
                        tasks: calendar.shownTasks(model.data.tasks, filters: model.filters, now: model.now),
                        now: model.now, rowHeight: 26
                    )
                    .padding(.horizontal, 14 * s)
                    .padding(.top, 6 * s)
                }
                if let sync = model.services?.sync {
                    AccountSidebarItem(sync: sync) { model.present.settings = true }
                }
            }
        }
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        .onGeometryChange(for: Bool.self) { [s] in $0.size.height >= 620 * s } action: { tall = $0 }
    }
}
#endif
