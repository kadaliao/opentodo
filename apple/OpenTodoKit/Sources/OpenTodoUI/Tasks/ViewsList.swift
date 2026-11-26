// The views of the tasks module — 今天 / 明天 / 最近7天 / 收集箱, the lists,
// the filters, the tags, then 已完成 and 垃圾桶 — each with its number of
// open tasks (sidebar.dart). As the sidebar on macOS and iPad (`.sidebar`:
// rows selected in place) and as the first screen of the tasks tab on
// iPhone (`.phone`: rows push the view).
//
// Lists: 添加清单 (the + by the header), right-click / long-press for
// 编辑清单 and 删除清单, drag to reorder. Filters: 添加过滤器 and 编辑 open
// the filter editor (the search engineer's), 删除 asks first.

import OpenTodoData
import OpenTodoDomain
import SwiftUI

struct ViewsList: View {
    enum Mode { case sidebar, phone }

    @Environment(AppModel.self) private var model
    var mode: Mode

    var body: some View {
        Group {
            switch mode {
            case .sidebar:
                List(selection: Binding(get: { model.view }, set: { if let v = $0 { model.select(v) } })) {
                    content
                }
                .listStyle(.sidebar)
            case .phone:
                List { content }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #endif
            }
        }
    }

    @ViewBuilder private var content: some View {
        Section {
            ForEach([SmartKind.today, .tomorrow, .next7, .inbox], id: \.self) { kind in
                row(.smart(kind), kind.title, icon: .smart(kind, style: iconStyle))
            }
        }
        Section {
            ForEach(model.lists) { list in
                row(.list(list.id), list.name, icon: .list(list, style: iconStyle))
                    .contextMenu {
                        Button("编辑清单", systemImage: "pencil") { model.present.listEditor = ListEditorRequest(list: list) }
                        Button("删除清单", systemImage: "trash", role: .destructive) { model.askDeleteList(list) }
                    }
            }
            .onMove { from, to in
                guard let i = from.first else { return }
                let id = model.lists[i].id
                model.run { await model.moveList(id, to: to) }
            }
            if model.lists.isEmpty {
                hint("用清单把任务分类，比如“工作”“购物”")
            }
        } header: {
            header("清单", add: "添加清单") { model.present.listEditor = ListEditorRequest() }
        }
        Section {
            ForEach(model.filters) { f in
                row(.filter(f.id), f.name, icon: .filter(style: iconStyle))
                    .contextMenu {
                        Button("编辑过滤器", systemImage: "slider.horizontal.3") { model.editFilter(f) }
                        Button("删除过滤器", systemImage: "trash", role: .destructive) { model.askDeleteFilter(f) }
                    }
            }
            .onMove { from, to in
                guard let i = from.first else { return }
                let id = model.filters[i].id
                model.run { await model.moveFilter(id, to: to) }
            }
            if model.filters.isEmpty {
                hint("按清单、日期、优先级、标签筛出任务，比如“本周的重要工作”")
            }
        } header: {
            header("过滤器", add: "添加过滤器") { model.editFilter() }
        }
        if !model.tags.isEmpty {
            Section {
                ForEach(model.tags, id: \.self) { tag in
                    row(.tag(tag), tag, icon: .tag(style: iconStyle))
                }
            } header: {
                Text("标签").uiDefaultFont(Self.headerFont, weight: .semibold)
            }
        }
        Section {
            row(.smart(.completed), SmartKind.completed.title, icon: .smart(.completed, style: iconStyle), counted: false)
            row(.smart(.trash), SmartKind.trash.title, icon: .smart(.trash, style: iconStyle), counted: false)
        }
    }

    private var iconStyle: ViewIcon.Style { mode == .phone ? .badge : .plain }

    @ViewBuilder
    private func row(_ view: ViewRef, _ title: String, icon: ViewIcon, counted: Bool = true) -> some View {
        let count = counted ? model.count(of: view) : 0
        let label = Label {
            Text(title).lineLimit(1)
        } icon: {
            icon
        }
        switch mode {
        case .sidebar:
            label
                .modifier(SidebarBadge(count: count))
                .listItemTint(icon.tint.map(ListItemTint.fixed) ?? .monochrome)
                .tag(view)
        case .phone:
            NavigationLink(value: PhoneRoute.view(view)) {
                label
                    .labelStyle(PhoneRowLabelStyle())
                    .badge(count)
            }
        }
    }

    /// A section header with a + at its end.
    private func header(_ title: String, add: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(add, systemImage: "plus", action: action)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(add)
        }
        .uiDefaultFont(Self.headerFont, weight: .semibold)
    }

    /// The sidebar draws its section titles this size at 标准.
    private static let headerFont = Font.TextStyle.subheadline

    private func hint(_ text: String) -> some View {
        Text(text)
            .uiFont(.caption)
            .foregroundStyle(.secondary)
            .selectionDisabled()
    }
}

/// The count at the end of a sidebar row. The system draws it in a size of
/// its own, so at the other 界面大小 it's given one that grows.
private struct SidebarBadge: ViewModifier {
    let count: Int
    @Environment(\.uiScale) private var s

    func body(content: Content) -> some View {
        if s == 1 {
            content.badge(count)
        } else {
            content.badge(count == 0 ? nil : Text("\(count)").font(.ui(.subheadline, scale: s)))
        }
    }
}

/// The iOS list rows: a 30pt badge icon, the title beside it.
private struct PhoneRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
            configuration.title
        }
        .padding(.vertical, 2)
    }
}
