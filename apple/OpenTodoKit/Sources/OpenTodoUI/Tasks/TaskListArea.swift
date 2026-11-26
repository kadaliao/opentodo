// The middle of the tasks module: one view's tasks, laid out as the view's
// `ViewPrefs.layout` says — a list (`TaskListView`), a board or a
// timeline — with the view's title and toolbar (显示选项, 新建任务, and
// 编辑过滤器 / 清空 where they apply).
//
// To plug a layout in, replace its placeholder in `LayoutContent` — one
// line. The layouts offered for a view are `layouts(for:)` (a board only
// for a list, as in the Flutter version).

import OpenTodoData
import OpenTodoDomain
import SwiftUI

struct TaskListArea: View {
    @Environment(AppModel.self) private var model
    var view: ViewRef

    var body: some View {
        let layout = model.prefs(for: view).layoutIn(view)
        LayoutContent(view: view, layout: layout)
            // Every layout: Esc, and on iPhone the bottom bar and 完成 (Flutter's BatchBar is on the whole pane).
            .modifier(TaskListPicking(view: view))
            .navigationTitle(model.title(of: view))
            #if os(macOS)
            .navigationSubtitle(subtitle)
            #else
            // The timeline isn't a scrolling list: a large title would sit
            // over its header (and it needs the height).
            .navigationBarTitleDisplayMode(layout == .timeline ? .inline : .large)
            #endif
            .toolbar { toolbar }
    }

    private var subtitle: String {
        let open = model.count(of: view)
        return open == 0 ? "" : "\(open) 个任务"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if case .filter(let id) = view, let filter = model.filtersById[id] {
                Button("编辑过滤器", systemImage: "slider.horizontal.3") { model.editFilter(filter) }
                    .help("编辑过滤器")
            }
            if view == .smart(.trash), !model.sections(for: view).isEmpty {
                Button("清空", systemImage: "trash.slash") { model.askEmptyTrash() }
                    .help("清空垃圾桶")
            }
            if !groupingsFor(view).isEmpty || arrangedListId(view) != nil {
                ViewOptionsMenu(view: view)
            }
            // While picking on a phone the bottom bar has the actions instead.
            if canQuickAdd(view) && !(model.width == .compact && model.selection.isPicking) {
                Button("新建任务", systemImage: "plus") { model.requestQuickAdd() }
                    .help("新建任务 (⌘N)")
            }
        }
    }
}

/// The view's tasks in its layout.
struct LayoutContent: View {
    var view: ViewRef
    var layout: ListLayout

    var body: some View {
        switch layout {
        case .list: TaskListView(view: view)
        case .board: ListBoard(view: view)
        case .timeline: TaskTimeline(view: view)
        }
    }
}


/// The layouts `view` can be shown in: a list's are list, board and
/// timeline; other views' list and timeline; 已完成 and 垃圾桶 only the list.
func layouts(for view: ViewRef) -> [ListLayout] {
    if arrangedListId(view) != nil { return [.list, .board, .timeline] }
    return groupingsFor(view).isEmpty ? [.list] : [.list, .timeline]
}

/// 显示选项 (⋯): how the view is laid out, grouped and sorted, whether 已完成
/// shows, and a list's 添加分组. Choices are kept per view in `ViewPrefs`
/// (except 显示已完成, which is for this window only).
struct ViewOptionsMenu: View {
    @Environment(AppModel.self) private var model
    var view: ViewRef

    var body: some View {
        let prefs = model.prefs(for: view)
        let layout = prefs.layoutIn(view)
        let groupings = layout == .board ? [] : (layout == .timeline ? timelineGroupingsFor(view) : groupingsFor(view))
        let grouping = layout == .timeline ? prefs.timelineGroupingIn(view) : prefs.groupingIn(view)
        Menu {
            let offered = layouts(for: view)
            if offered.count > 1 {
                Picker("显示为", selection: Binding(get: { layout }, set: { model.settings.setLayout(view, $0) })) {
                    ForEach(offered, id: \.self) { l in
                        Label(l.title, systemImage: l.symbol).tag(l)
                    }
                }
                .pickerStyle(.inline)
            }
            if groupings.count > 1, let grouping {
                Picker(selection: Binding(get: { grouping }, set: { model.settings.setGrouping(view, $0) })) {
                    ForEach(groupings, id: \.self) { g in
                        Text(g.menuTitle).tag(g)
                    }
                } label: {
                    Label("分组：\(grouping.label)", systemImage: "rectangle.stack")
                }
                .pickerStyle(.menu)
            }
            if let sort = prefs.sortIn(view) {
                Picker(selection: Binding(get: { sort }, set: { model.settings.setSort(view, $0) })) {
                    ForEach(sortsFor(view), id: \.self) { s in
                        Text(s == .manual ? "自定义（拖动）" : "按\(s.label)").tag(s)
                    }
                } label: {
                    Label("排序：\(sort.label)", systemImage: "arrow.up.arrow.down")
                }
                .pickerStyle(.menu)
            }
            if layout == .list, !groupingsFor(view).isEmpty {
                Toggle(isOn: Binding(get: { model.taskList.showsDone(view) }, set: { model.taskList.setShowsDone($0, view) })) {
                    Label("显示已完成", systemImage: "checkmark.circle")
                }
            }
            if let listId = arrangedListId(view) {
                Divider()
                Button("添加分组", systemImage: "plus.rectangle.on.rectangle") { model.askAddSection(listId) }
            }
        } label: {
            Label("显示选项", systemImage: "ellipsis")
        }
        .help("显示选项")
    }
}

extension ListLayout {
    var title: String {
        switch self {
        case .list: "列表"
        case .board: "看板"
        case .timeline: "时间线"
        }
    }

    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .board: "rectangle.split.3x1"
        case .timeline: "chart.bar.xaxis"
        }
    }
}

extension TaskGrouping {
    /// As the Flutter menu words it.
    var menuTitle: String {
        switch self {
        case .sections: "自定义分组"
        case .none: "不分组"
        default: "按\(label)"
        }
    }
}
