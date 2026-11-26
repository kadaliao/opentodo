// The tasks module. Wide (macOS, iPad): sidebar / list / detail in a
// `NavigationSplitView`. Compact (iPhone, narrow iPad windows): a
// `NavigationStack` from the views to a list to a task, its path kept in
// `AppModel.phonePath`.

import OpenTodoDomain
import SwiftUI

struct TasksScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.width == .compact {
            PhoneTasks()
        } else {
            TasksSplitView()
        }
    }
}

struct TasksSplitView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.uiScale) private var s
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if wantsWidth {
                // A board or a timeline wants the width: the detail shows
                // only for a selected task, beside it.
                NavigationSplitView(columnVisibility: $columns) {
                    sidebar
                } detail: {
                    content.inspector(isPresented: inspecting) {
                        detail.inspectorColumnWidth(min: 300, ideal: 380, max: 480 * s)
                            // Flutter's 关闭详情 beside a board.
                            .toolbar {
                                // The inspector's toolbar items stay in the
                                // window's toolbar while it's closed.
                                if inspecting.wrappedValue {
                                    ToolbarItem(placement: .primaryAction) {
                                        Button("关闭详情", systemImage: "xmark") { inspecting.wrappedValue = false }
                                            .help("关闭详情")
                                    }
                                }
                            }
                    }
                }
                #if os(macOS)
                .toolbar { searchButton }
                #endif
            } else {
                NavigationSplitView(columnVisibility: $columns) {
                    sidebar
                } content: {
                    // The three minimums fit the window's smallest width
                    // (760, RootView): wider ones overlapped there, the
                    // sidebar's rows cut off on the left and the detail's
                    // on the right. So of the three only the sidebar's
                    // ideal width grows with 界面大小 (its rows have no room
                    // to spare); the list and the detail share what's left.
                    content.navigationSplitViewColumnWidth(min: 280, ideal: 400)
                } detail: {
                    detail.navigationSplitViewColumnWidth(min: 280, ideal: 380)
                        #if os(macOS)
                        // Search at the far end of the toolbar, as in Mail
                        // and Notes; the spacer also keeps the list's items
                        // over the list column when the detail has none.
                        .toolbar {
                            ToolbarSpacer(.flexible)
                            searchButton
                        }
                        #endif
                }
            }
        }
    }

    #if os(macOS)
    private var searchButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("搜索", systemImage: "magnifyingglass") { model.requestSearch() }
                .help("搜索（⌘F）")
        }
    }
    #endif

    /// The view on screen is laid out as a board or a timeline.
    private var wantsWidth: Bool {
        model.prefs(for: model.view).layoutIn(model.view) != .list
    }

    private var inspecting: Binding<Bool> {
        Binding(get: { model.selectedTaskId != nil || model.selection.isActive },
                set: { if !$0 { model.selectedTaskId = nil; model.selection.clear() } })
    }

    private var sidebar: some View {
        ViewsList(mode: .sidebar)
            .moduleBar()
            .modifier(AccountFooter())
            .navigationSplitViewColumnWidth(min: 180, ideal: 230 * s, max: 320 * s)
            #if os(iOS)
            .navigationTitle("任务")
            // iPad: 设置 (macOS has the Settings window and the account row).
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("设置", systemImage: "gearshape") { model.present.settings = true }
                }
            }
            #endif
    }

    private var content: some View {
        TaskListArea(view: model.view)
    }

    private var detail: some View {
        Group {
            if model.selection.isActive {
                BatchDetail()
            } else if let id = model.selectedTaskId {
                TaskDetailView(taskId: id)
            } else {
                EmptyState.noTaskSelected
            }
        }
    }
}

struct PhoneTasks: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.phonePath) {
            ViewsList(mode: .phone)
                .navigationTitle("任务")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("设置", systemImage: "gearshape") { model.present.settings = true }
                    }
                }
                .navigationDestination(for: PhoneRoute.self) { route in
                    switch route {
                    case .view(let v): TaskListArea(view: v)
                    case .task(let id): TaskDetailView(taskId: id)
                    }
                }
        }
        .onChange(of: model.phonePath) { model.phonePathChanged() }
        .task {
            if model.taskList.prefill != nil { model.present.quickAdd = true }
        }
    }
}

/// macOS: the account at the bottom of the sidebar (data's
/// `AccountSidebarItem`); a click opens 设置.
struct AccountFooter: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        #if os(macOS)
        // Hard edge: with the soft one the rows under the bar show through
        // as blurred ghosts right behind the account's icon and name.
        content.safeAreaBar(edge: .bottom, spacing: 0) {
            if let sync = model.services?.sync {
                AccountSidebarItem(sync: sync) { model.present.settings = true }
            }
        }
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        #else
        content
        #endif
    }
}
