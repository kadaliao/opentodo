// The batch actions (批量操作) for picked tasks. Spec:
// `app/lib/ui/batch_actions.dart`; the rules are in `BatchModel.swift`.
//
// - `BatchPanel`: what the detail column shows on a wide window while
//   tasks are picked — 已选择 N 项 and 取消, the date / priority / list /
//   tags of the picked tasks (each changes them all), and 完成, 置顶,
//   复制标题, 删除.
// - `BatchBar` (macOS, a narrower window) and `.batchBottomBar(…)` (iOS,
//   the system bottom toolbar): the same along the bottom of the list,
//   with what doesn't fit under 更多.
//
// Both take values and report `BatchAction`s; the caller writes them with
// `TaskRepo`, clears the selection after 完成 and 删除, and shows the
// undo toast:
//
//     BatchPanel(selection: BatchSelection(ids: model.picked, tasks: model.tasks),
//                lists: model.lists, knownTags: model.tags, today: model.today) { action in
//         model.perform(action)
//     }

import OpenTodoDomain
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What the batch views need besides the selection.
struct BatchContext {
    let selection: BatchSelection
    let lists: [TaskList]
    let knownTags: [String]
    let today: Day
    let onAction: (BatchAction) -> Void

    var listsById: [String: TaskList] { Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    func copyTitles() {
        let text = selection.titlesText
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        onAction(.copiedTitles(count: selection.tasks.count))
    }
}

// MARK: - Menus shared by the panel and the bar

/// 今天 / 明天 / 下周一 / 选择日期… / 清除日期.
private struct DateMenuItems: View {
    let context: BatchContext
    let pick: () -> Void

    var body: some View {
        ForEach(BatchDateChoice.allCases, id: \.self) { c in
            if c == .clear { Divider() }
            Button(role: c == .clear ? .destructive : nil) {
                if c == .pick { pick() } else { context.onAction(context.selection.setDue(c.day(today: context.today))) }
            } label: {
                Label(c.title, systemImage: c.symbol)
            }
        }
    }
}

private struct PriorityMenuItems: View {
    let context: BatchContext

    var body: some View {
        ForEach([Priority.high, .medium, .low, .none], id: \.self) { p in
            Toggle(isOn: Binding { context.selection.priority == p } set: { _ in
                context.onAction(context.selection.setPriority(p))
            }) {
                Label(priorityName(p), systemImage: p == .none ? "flag.slash" : "flag.fill")
            }
            .tint(Palette.priority(p))
        }
    }
}

private struct ListMenuItems: View {
    let context: BatchContext

    private func item(_ id: String, _ title: String) -> some View {
        Toggle(title, isOn: Binding { context.selection.listId == id } set: { _ in
            context.onAction(context.selection.move(to: id))
        })
    }

    var body: some View {
        item(inboxListId, "收集箱")
        Divider()
        ForEach(context.lists.filter { $0.id != inboxListId }) { l in
            item(l.id, [l.textEmoji, l.name].compactMap { $0 }.joined(separator: " "))
        }
    }
}

// MARK: - The panel

public struct BatchPanel: View {
    @Environment(\.uiScale) private var s
    private let context: BatchContext
    @State private var pickingDay = false
    @State private var editingTags = false
    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - selection: the picked tasks (`BatchSelection(ids:tasks:)`).
    ///   - lists: every list, for 移动到 (收集箱 is offered anyway).
    ///   - knownTags: every tag in use, for the tag editor.
    ///   - today: for 今天 / 明天 / 下周一.
    ///   - onAction: what the person did; see `BatchAction`.
    public init(selection: BatchSelection, lists: [TaskList], knownTags: [String], today: Day,
                onAction: @escaping (BatchAction) -> Void) {
        context = BatchContext(selection: selection, lists: lists, knownTags: knownTags, today: today, onAction: onAction)
    }

    /// Debug: open with the tag editor showing.
    init(context: BatchContext, editingTags: Bool) {
        self.context = context
        _editingTags = State(initialValue: editingTags)
    }

    private var selection: BatchSelection { context.selection }

    public var body: some View {
        Form {
            Section {
                LabeledContent {
                    Menu {
                        DateMenuItems(context: context) { pickingDay = true }
                    } label: {
                        Text(dueSummary)
                    }
                    .fixedSize()
                    .popover(isPresented: $pickingDay) { dayPicker }
                } label: {
                    BatchRowLabel("日期", symbol: "calendar", tint: .red)
                }
                LabeledContent {
                    Menu {
                        PriorityMenuItems(context: context)
                    } label: {
                        Text(selection.priorityTitle)
                    }
                    .fixedSize()
                } label: {
                    BatchRowLabel("优先级", symbol: "flag.fill",
                                  tint: selection.priority.map { $0 == .none ? Color.gray : Palette.priority($0) } ?? .gray,
                                  tintOnMac: true)
                }
                LabeledContent {
                    Menu {
                        ListMenuItems(context: context)
                    } label: {
                        Text(selection.listTitle(context.listsById))
                    }
                    .fixedSize()
                } label: {
                    BatchRowLabel("清单", symbol: "tray.full.fill", macSymbol: "folder", tint: .blue)
                }
                Button {
                    editingTags = true
                } label: {
                    LabeledContent {
                        HStack(spacing: 6 * s) {
                            if selection.tags.isEmpty {
                                Text("添加").foregroundStyle(.secondary)
                            } else {
                                ForEach(selection.tags.prefix(4), id: \.self) { TagLabel($0) }
                                if selection.tags.count > 4 { Text("…").foregroundStyle(.secondary) }
                            }
                            Image(systemName: "chevron.right")
                                .uiFont(.caption, weight: .semibold)
                                .foregroundStyle(.tertiary)
                        }
                    } label: {
                        BatchRowLabel("标签", symbol: "number", tint: .orange)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $editingTags) { tagsEditor }
            } header: {
                header
            }
            Section {
                actionTiles
                #if os(iOS)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                #endif
            }
        }
        .formStyle(.grouped)
        .environment(\.locale, ScheduleEditorView.locale)
    }

    @ViewBuilder private var tiles: some View {
        ActionTile("完成", symbol: "checkmark.circle") { context.onAction(selection.complete) }
            .disabled(selection.open.isEmpty)
        ActionTile(selection.allPinned ? "取消置顶" : "置顶", symbol: selection.allPinned ? "pin.slash" : "pin") {
            context.onAction(selection.togglePin)
        }
        .disabled(selection.open.isEmpty)
        ActionTile("复制标题", symbol: "doc.on.doc") { context.copyTitles() }
        ActionTile("删除", symbol: "trash", role: .destructive) { context.onAction(selection.trash) }
    }

    /// iOS: a 2 × 2 grid of cards on the grouped background; macOS: one
    /// row of buttons in the section's box.
    private var actionTiles: some View {
        #if os(iOS)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10 * s), GridItem(.flexible(), spacing: 10 * s)], spacing: 10 * s) {
            tiles
        }
        #else
        HStack(spacing: 4 * s) { tiles }
        #endif
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("已选择 \(selection.count) 项")
                .uiFont(.title3, weight: .semibold)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Spacer()
            Button("取消") { context.onAction(.clearSelection) }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
        }
        .textCase(nil)
        .padding(.bottom, 4 * s)
    }

    /// 今天 / 多个日期 / 无日期: what the picked tasks' dates have in common.
    private var dueSummary: String {
        let dates = Set(selection.tasks.map(\.dueDate))
        guard dates.count == 1, let only = dates.first else { return dates.isEmpty ? "无日期" : "多个日期" }
        return only.map { dateLabel($0, today: context.today) } ?? "无日期"
    }

    private var dayPicker: some View {
        DayPickerView(initial: context.today, today: context.today) { day in
            pickingDay = false
            context.onAction(selection.setDue(day))
        } onCancel: {
            pickingDay = false
        }
        .modifier(BatchSheetStyle())
    }

    private var tagsEditor: some View {
        BatchTagsView(BatchTagsEditor(tasks: selection.tasks, known: context.knownTags)) { action in
            editingTags = false
            if let action { context.onAction(action) }
        }
        .modifier(BatchSheetStyle())
    }
}

/// A row title with its symbol: on iOS coloured as the date dialog's rows
/// are; on the Mac plain, as the task detail beside it has them (only the
/// priority's flag keeps its colour there too).
private struct BatchRowLabel: View {
    let title: String
    let symbol: String
    let macSymbol: String?
    let tint: Color
    let tintOnMac: Bool

    init(_ title: String, symbol: String, macSymbol: String? = nil, tint: Color, tintOnMac: Bool = false) {
        self.title = title
        self.symbol = symbol
        self.macSymbol = macSymbol
        self.tint = tint
        self.tintOnMac = tintOnMac
    }

    var body: some View {
        #if os(iOS)
        ScheduleRowLabel(title, symbol: symbol, tint: tint)
        #else
        Label {
            Text(title)
        } icon: {
            Image(systemName: macSymbol ?? symbol)
                .foregroundStyle(tintOnMac ? AnyShapeStyle(tint) : AnyShapeStyle(.primary))
        }
        #endif
    }
}

/// A big button of the panel's grid: symbol over title.
private struct ActionTile: View {
    @Environment(\.uiScale) private var s
    let title: String
    let symbol: String
    let role: ButtonRole?
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    init(_ title: String, symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.role = role
        self.action = action
    }

    #if os(iOS)
    static let height: CGFloat = 76
    private var background: AnyShapeStyle { AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)) }
    #else
    static let height: CGFloat = 60
    private var background: AnyShapeStyle { hovering ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear) }
    #endif

    var body: some View {
        Button(role: role, action: action) {
            VStack(spacing: 6 * s) {
                Image(systemName: symbol).uiFont(.title2)
                Text(title).uiFont(.callout)
            }
            .foregroundStyle(role == .destructive ? Color.red : Color.accentColor)
            .opacity(enabled ? 1 : 0.4)
            .frame(maxWidth: .infinity, minHeight: Self.height * s)
            .background(background, in: RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12 * s, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

// MARK: - The bar

/// The buttons along the bottom: 取消选择 and the count, then 日期,
/// 优先级, 移动到, 完成, 删除, and 更多 (全选, 标签…, 置顶 / 取消置顶, 复制标题).
private struct BatchBarItems: View {
    let context: BatchContext
    @Binding var pickingDay: Bool
    @Binding var editingTags: Bool

    private var selection: BatchSelection { context.selection }

    var body: some View {
        Button("取消选择", systemImage: "xmark") { context.onAction(.clearSelection) }
            .help("取消选择")
        Text("\(selection.count) 项")
            .uiFont(.headline)
            .monospacedDigit()
            .fixedSize()
        Spacer()
        Menu("设置日期", systemImage: "calendar") {
            DateMenuItems(context: context) { pickingDay = true }
        }
        .help("设置日期")
        Menu("优先级", systemImage: "flag") {
            PriorityMenuItems(context: context)
        }
        .help("优先级")
        Menu("移动到…", systemImage: "folder") {
            ListMenuItems(context: context)
        }
        .help("移动到…")
        Button("完成", systemImage: "checkmark.circle") { context.onAction(selection.complete) }
            .help("完成")
            .disabled(selection.open.isEmpty)
        Button("删除", systemImage: "trash", role: .destructive) { context.onAction(selection.trash) }
            .help("删除")
            .tint(.red)
        Menu("更多操作", systemImage: "ellipsis.circle") {
            Button("全选", systemImage: "checklist") { context.onAction(.selectAll) }
            Button("标签…", systemImage: "number") { editingTags = true }
            Button(selection.allPinned ? "取消置顶" : "置顶", systemImage: selection.allPinned ? "pin.slash" : "pin") {
                context.onAction(selection.togglePin)
            }
            .disabled(selection.open.isEmpty)
            Button("复制标题", systemImage: "doc.on.doc") { context.copyTitles() }
        }
        .help("更多操作")
    }
}

#if os(macOS)
/// macOS, a narrower window: the bar under the list.
public struct BatchBar: View {
    @Environment(\.uiScale) private var s
    private let context: BatchContext
    @State private var pickingDay = false
    @State private var editingTags = false

    /// Same inputs as `BatchPanel`.
    public init(selection: BatchSelection, lists: [TaskList], knownTags: [String], today: Day,
                onAction: @escaping (BatchAction) -> Void) {
        context = BatchContext(selection: selection, lists: lists, knownTags: knownTags, today: today, onAction: onAction)
    }

    public var body: some View {
        HStack(spacing: 14 * s) {
            BatchBarItems(context: context, pickingDay: $pickingDay, editingTags: $editingTags)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .uiFont(.title3)
        .imageScale(.large)
        .padding(.horizontal, 14 * s)
        .frame(height: 44 * s)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .popover(isPresented: $pickingDay, arrowEdge: .top) {
            DayPickerView(initial: context.today, today: context.today) { day in
                pickingDay = false
                context.onAction(context.selection.setDue(day))
            } onCancel: { pickingDay = false }
        }
        .popover(isPresented: $editingTags, arrowEdge: .top) {
            BatchTagsView(BatchTagsEditor(tasks: context.selection.tasks, known: context.knownTags)) { action in
                editingTags = false
                if let action { context.onAction(action) }
            }
        }
        .environment(\.locale, ScheduleEditorView.locale)
    }
}
#endif

#if os(iOS)
extension View {
    /// iOS: the batch actions in the system's bottom toolbar, while
    /// `selection` is non-nil. Put it on the list inside its
    /// `NavigationStack` (and hide the add button meanwhile, as the Dart
    /// version does). Same inputs as `BatchPanel`.
    public func batchBottomBar(selection: BatchSelection?, lists: [TaskList], knownTags: [String], today: Day,
                               onAction: @escaping (BatchAction) -> Void) -> some View {
        modifier(BatchBottomBar(
            context: selection.map {
                BatchContext(selection: $0, lists: lists, knownTags: knownTags, today: today, onAction: onAction)
            },
            editingTags: false
        ))
    }
}

struct BatchBottomBar: ViewModifier {
    let context: BatchContext?
    @State private var pickingDay = false
    @State var editingTags: Bool

    func body(content: Content) -> some View {
        content
            .toolbar {
                if let context {
                    ToolbarItemGroup(placement: .bottomBar) {
                        BatchBarItems(context: context, pickingDay: $pickingDay, editingTags: $editingTags)
                    }
                }
            }
            .toolbar(context == nil ? .hidden : .visible, for: .bottomBar)
            .sheet(isPresented: $pickingDay) {
                if let context {
                    DayPickerView(initial: context.today, today: context.today) { day in
                        pickingDay = false
                        context.onAction(context.selection.setDue(day))
                    } onCancel: { pickingDay = false }
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $editingTags) {
                if let context {
                    BatchTagsView(BatchTagsEditor(tasks: context.selection.tasks, known: context.knownTags)) { action in
                        editingTags = false
                        if let action { context.onAction(action) }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
    }
}
#endif

/// Popovers on macOS and iPad, sheets on iPhone.
struct BatchSheetStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .frame(idealWidth: 380, idealHeight: 560)
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.medium, .large])
        #else
        content
        #endif
    }
}

// MARK: - Tags

/// N 个任务的标签: a tick when all have it, a dash when some do; ticking
/// adds to all, unticking takes off all; a new tag can be typed in.
/// `onDone` gets the `.setTags` action, nil when cancelled.
struct BatchTagsView: View {
    @Environment(\.uiScale) private var s
    @State private var editor: BatchTagsEditor
    @State private var newTag = ""
    let onDone: (BatchAction?) -> Void

    init(_ editor: BatchTagsEditor, onDone: @escaping (BatchAction?) -> Void) {
        _editor = State(initialValue: editor)
        self.onDone = onDone
    }

    private var title: String { "\(editor.tasks.count) 个任务的标签" }

    private func symbol(_ state: Bool?) -> String {
        #if os(macOS)
        switch state { case true: "checkmark.square.fill"; case nil: "minus.square.fill"; default: "square" }
        #else
        switch state { case true: "checkmark.circle.fill"; case nil: "minus.circle.fill"; default: "circle" }
        #endif
    }

    private var rows: some View {
        ForEach(editor.tags, id: \.self) { tag in
            let state = editor.state(tag)
            Button {
                editor.toggle(tag)
            } label: {
                HStack(spacing: 10 * s) {
                    Image(systemName: symbol(state))
                        .uiFont(.title3)
                        .foregroundStyle(state == false ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                    Text(tag).foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(state == true ? "全部有" : state == nil ? "部分有" : "都没有")
        }
    }

    private var newTagField: some View {
        HStack {
            Image(systemName: "number").foregroundStyle(.secondary)
            TextField("新标签", text: $newTag)
                .onSubmit(addNew)
                #if os(iOS)
                .submitLabel(.done)
                #endif
            Button("添加标签", systemImage: "plus.circle.fill", action: addNew)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func addNew() {
        if editor.addNew(newTag) { newTag = "" }
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            List {
                Section {
                    rows
                } footer: {
                    Group {
                        Text("勾上就给全部任务加上，去掉就从全部任务拿掉；横线表示只有一部分有。")
                    }
                    .uiDefaultFont(.subheadline)
                }
                Section { newTagField }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { onDone(nil) } }
                ToolbarItem(placement: .confirmationAction) { Button(role: .confirm) { onDone(editor.action) } }
            }
        }
        #else
        VStack(alignment: .leading, spacing: 0) {
            Text(title).uiFont(.headline).padding([.horizontal, .top], 14 * s).padding(.bottom, 8 * s)
            ScrollView {
                VStack(alignment: .leading, spacing: 8 * s) { rows }
                    .padding(.horizontal, 14 * s)
            }
            .frame(maxHeight: 260 * s)
            .fixedSize(horizontal: false, vertical: true)
            Divider().padding(.top, 8 * s)
            newTagField.textFieldStyle(.plain).padding(.horizontal, 14 * s).frame(height: 36 * s)
            Divider()
            HStack {
                Spacer()
                Button("取消") { onDone(nil) }.keyboardShortcut(.cancelAction)
                Button("确定") { onDone(editor.action) }.keyboardShortcut(.defaultAction)
            }
            .padding(12 * s)
        }
        .frame(width: 280 * s)
        #endif
    }
}
