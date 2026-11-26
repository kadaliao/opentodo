// A list as a board (看板), ported from `app/lib/ui/board_view.dart`: a
// column per section (`boardColumns`), cards dragged within and between
// them, columns dragged by their tops, a field per column for adding, the
// finished cards folded away at the bottom of each, and 添加分组 at the far
// right. It scrolls sideways; each column scrolls on its own. A phone shows
// one column and a bit of the next, and snaps column by column.
//
// A self-contained component: it takes values and reports what the person
// did through `BoardActions`; it reads and writes nothing itself.

import OpenTodoDomain
import SwiftUI

public struct BoardView<TaskMenu: View>: View {
    @Environment(\.uiScale) private var s
    let listId: String
    let columns: [BoardColumn]
    let sort: TaskSort
    let now: LocalDateTime
    let selection: BoardSelection
    let progress: [String: ChecklistProgress]
    let actions: BoardActions
    let taskMenu: (TodoTask) -> TaskMenu

    let sharedDrag: DragController?
    @State private var ownDrag = DragController()
    @State private var dialog: SectionDialog?
    @State private var width: CGFloat = 0

    /// - Parameters:
    ///   - listId: the list shown.
    ///   - columns: `boardColumns(listId, tasks, sections, sort: sort)`.
    ///   - sort: the list's order; anything but `.manual` makes a drop only
    ///     change the section.
    ///   - now: for dates (今天, overdue in red).
    ///   - selection: the open card, or the picked ones.
    ///   - progress: checklist progress by task id (`ChecklistProgress.of`).
    ///   - drag: a drag space to share with views around the board; its
    ///     own when nil.
    ///   - taskMenu: a card's context menu (right click; a long press that
    ///     doesn't move on a touch screen).
    public init(
        listId: String,
        columns: [BoardColumn],
        sort: TaskSort = .manual,
        now: LocalDateTime,
        selection: BoardSelection = BoardSelection(),
        progress: [String: ChecklistProgress] = [:],
        actions: BoardActions = BoardActions(),
        drag: DragController? = nil,
        @ViewBuilder taskMenu: @escaping (TodoTask) -> TaskMenu
    ) {
        self.sharedDrag = drag
        self.listId = listId
        self.columns = columns
        self.sort = sort
        self.now = now
        self.selection = selection
        self.progress = progress
        self.actions = actions
        self.taskMenu = taskMenu
    }

    private var drag: DragController { sharedDrag ?? ownDrag }

    public var body: some View {
        let columnWidth = BoardLayout.columnWidth(for: width, scale: s)
        let phone = width > 0 && width < BoardLayout.phoneWidth
        let picked = BoardLayout.picked(columns, selection)
        let sections = BoardLayout.sections(columns)
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12 * s) {
                ForEach(columns, id: \.group.section?.id) { column in
                    BoardColumnView(
                        listId: listId,
                        column: column,
                        sections: sections,
                        group: BoardLayout.drop(column, listId: listId, sort: sort),
                        now: now,
                        selection: selection,
                        picked: picked,
                        progress: progress,
                        width: columnWidth,
                        actions: actions,
                        dialog: dialogBinding,
                        taskMenu: taskMenu
                    )
                    .frame(width: columnWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                Button {
                    dialogBinding.wrappedValue = .add(listId: listId)
                } label: {
                    Label("添加分组", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.top, 10 * s)
                .padding(.trailing, 8 * s)
            }
            .scrollTargetLayout()
            .padding(.bottom, 12 * s)
            .padding(.top, 4 * s)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: phone ? .alwaysByOne : .never))
        .scrollIndicators(.automatic)
        .dragAutoScroll("board", axis: .horizontal)
        .dragSpace(drag)
        .background(BoardStyle.boardBackground)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // The board's own dialogs only when the app has none of its own.
        .modifier(OwnSectionDialogs(enabled: actions.askSection == nil, dialog: $dialog, perform: actions.section))
        .onAppear { drag.onDrop = handle }
        .onChange(of: columns) { drag.onDrop = handle }
    }

    /// The dialogs go to the app's when it has its own.
    private var dialogBinding: Binding<SectionDialog?> {
        Binding {
            dialog
        } set: { d in
            dialog = d.flatMap(actions.route)
        }
    }

    private func handle(_ outcome: DropOutcome) {
        switch outcome {
        case .tasks(let plan): actions.drop(plan)
        case .sections(let orders): actions.section(.reorder(orders))
        }
    }
}

extension BoardView where TaskMenu == EmptyView {
    /// A board whose cards have no context menu.
    public init(
        listId: String,
        columns: [BoardColumn],
        sort: TaskSort = .manual,
        now: LocalDateTime,
        selection: BoardSelection = BoardSelection(),
        progress: [String: ChecklistProgress] = [:],
        actions: BoardActions = BoardActions(),
        drag: DragController? = nil
    ) {
        self.init(
            listId: listId, columns: columns, sort: sort, now: now, selection: selection,
            progress: progress, actions: actions, drag: drag, taskMenu: { _ in EmptyView() }
        )
    }
}

struct BoardColumnView<TaskMenu: View>: View {
    @Environment(\.uiScale) private var s
    let listId: String
    let column: BoardColumn
    /// The list's sections in order.
    let sections: [ListSection]
    let group: GroupDrop
    let now: LocalDateTime
    let selection: BoardSelection
    let picked: [TodoTask]
    let progress: [String: ChecklistProgress]
    let width: CGFloat
    let actions: BoardActions
    @Binding var dialog: SectionDialog?
    let taskMenu: (TodoTask) -> TaskMenu

    @State private var adding = false
    @State private var showDone = false
    @Environment(DragController.self) private var drag: DragController?
    @Environment(\.boardStart) private var start

    private var key: String { BoardLayout.key(column) }
    private var section: ListSection? { column.group.section }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if adding {
                BoardQuickAddField(title: column.group.title) { text in
                    if let add = BoardLayout.quickAdd(text, in: column, listId: listId) { actions.quickAdd(add) }
                } close: {
                    adding = false
                }
                .padding(.horizontal, 8 * s)
                .padding(.bottom, 8 * s)
            }
            ScrollView(.vertical) {
                cards
                    .padding(.horizontal, 8 * s)
                    .padding(.bottom, 8 * s)
            }
            .scrollIndicators(.never)
            .dragAutoScroll("column-\(key)", axis: .vertical)
        }
        .background {
            RoundedRectangle(cornerRadius: BoardStyle.columnRadius, style: .continuous)
                .fill(.fill.quaternary.opacity(0.7))
        }
        .overlay {
            // Out of manual order a drop only changes section: the whole
            // column lights up.
            if drag?.highlights(group.target) == true {
                RoundedRectangle(cornerRadius: BoardStyle.columnRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .opacity(section.map { drag?.isDragged(section: $0.id) == true } == true ? 0.4 : 1)
        .modifier(ColumnSectionDrop(section: section, sections: sections))
        .onAppear {
            if start.adding == key { adding = true }
            if start.showDone { showDone = true }
        }
    }

    private var header: some View {
        HStack(spacing: 6 * s) {
            Text(column.group.title)
                .uiFont(.headline)
                .lineLimit(1)
            Text(column.group.tasks.count, format: .number)
                .uiFont(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 4)
            Button {
                adding.toggle()
            } label: {
                Image(systemName: adding ? "xmark" : "plus")
                    .frame(width: 22 * s, height: 22 * s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("在“\(column.group.title)”里添加任务")
            .accessibilityLabel("在“\(column.group.title)”里添加任务")
            if let section {
                Menu {
                    SectionMenu(section: section, among: sections, horizontal: true, dialog: $dialog, perform: actions.section)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 22 * s, height: 22 * s)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("分组操作")
                .accessibilityLabel("分组操作")
            }
        }
        .foregroundStyle(.primary)
        .padding(.leading, 14 * s)
        .padding(.trailing, 8 * s)
        .padding(.vertical, 10 * s)
        .contentShape(Rectangle())
        // Cards dropped on the top go first; the column moves by its top.
        .dropSlot("head-\(key)", .taskArea(group, index: 0))
        .modifier(ColumnDragSource(section: section, title: column.group.title, count: column.group.tasks.count, width: width))
    }

    private var cards: some View {
        LazyVStack(alignment: .leading, spacing: 8 * s) {
            ForEach(Array(column.group.tasks.enumerated()), id: \.element.id) { i, task in
                card(task)
                    .taskDragSource(task, picked: picked) {
                        cardFace(task, selected: false).frame(width: width - 16 * s)
                    }
                    .opacity(drag?.isDragged(task.id) == true ? 0.3 : 1)
                    .dropSlot("row-\(task.id)", .taskRow(group, index: i), outset: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            // The rest of the column takes a drop at the end.
            endArea
                .dropSlot("end-\(key)", .taskArea(group, index: column.group.tasks.count))
            if !column.done.isEmpty { done }
        }
    }

    private var endArea: some View {
        Group {
            if column.group.tasks.isEmpty {
                Text("拖任务到这里")
                    .uiFont(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 80 * s)
                    .background {
                        RoundedRectangle(cornerRadius: BoardStyle.cardRadius, style: .continuous)
                            .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
            } else {
                Color.clear.frame(height: 40 * s)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var done: some View {
        Group {
            Button {
                withAnimation(.snappy) { showDone.toggle() }
            } label: {
                HStack(spacing: 6 * s) {
                    Image(systemName: "chevron.right")
                        .uiFont(.caption, weight: .semibold)
                        .rotationEffect(.degrees(showDone ? 90 : 0))
                    Text("已完成")
                    Text(column.done.count, format: .number).foregroundStyle(.tertiary).monospacedDigit()
                }
                .uiFont(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4 * s)
                .padding(.vertical, 4 * s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showDone ? "已展开" : "已折叠")
            if showDone {
                ForEach(column.done, id: \.id) { task in card(task) }
            }
        }
    }

    private func cardFace(_ task: TodoTask, selected: Bool) -> some View {
        BoardCard(task: task, selected: selected, now: now, progress: progress[task.id]) {
            actions.setDone(task, task.status == .open)
        }
    }

    private func card(_ task: TodoTask) -> some View {
        cardFace(task, selected: selection.isSelected(task.id))
            .onTapGesture { actions.tap(task.id, currentModifiers()) }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { actions.tap(task.id, []) }
            .contextMenu { taskMenu(task) }
    }
}

/// A column takes another section of the list dropped on its left half
/// (before it) or right half (after it).
private struct ColumnSectionDrop: ViewModifier {
    let section: ListSection?
    let sections: [ListSection]

    func body(content: Content) -> some View {
        if let section {
            content.dropSlot(
                "column-\(section.id)",
                .section(section, among: sections, axis: .horizontal),
                outset: EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
            )
        } else {
            content
        }
    }
}

/// A section's column is dragged by its top.
private struct ColumnDragSource: ViewModifier {
    @Environment(\.uiScale) private var s
    let section: ListSection?
    let title: String
    let count: Int
    let width: CGFloat

    func body(content: Content) -> some View {
        if let section {
            content.sectionDragSource(section) {
                HStack(spacing: 6 * s) {
                    Text(title).uiFont(.headline)
                    Text(count, format: .number).uiFont(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14 * s)
                .padding(.vertical, 12 * s)
                .frame(width: width)
                .background(RoundedRectangle(cornerRadius: BoardStyle.columnRadius, style: .continuous).fill(BoardStyle.cardFill))
            }
        } else {
            content
        }
    }
}

/// A column's own field for adding a task to it: Return adds and keeps the
/// field for the next one; Esc closes it.
struct BoardQuickAddField: View {
    @Environment(\.uiScale) private var s
    let title: String
    let add: (String) -> Void
    let close: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("添加任务，回车创建", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .submitLabel(.done)
            .onSubmit {
                add(text)
                text = ""
                focused = true
            }
            .onKeyPress(.escape) {
                close()
                return .handled
            }
            .padding(.horizontal, 12 * s)
            .padding(.vertical, 9 * s)
            .background {
                RoundedRectangle(cornerRadius: BoardStyle.cardRadius, style: .continuous)
                    .fill(BoardStyle.cardFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: BoardStyle.cardRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(focused ? 0.7 : 0.25), lineWidth: 1)
            }
            .accessibilityLabel("在“\(title)”里添加任务")
            .onAppear { focused = true }
    }
}

/// How columns start out, for the debug screens: one's field open, the
/// finished cards shown.
struct BoardStart: Hashable {
    var adding: String?
    var showDone = false
}

extension EnvironmentValues {
    @Entry var boardStart = BoardStart()
}

private struct OwnSectionDialogs: ViewModifier {
    let enabled: Bool
    @Binding var dialog: SectionDialog?
    let perform: (SectionAction) -> Void

    func body(content: Content) -> some View {
        if enabled { content.sectionDialogs($dialog, perform: perform) } else { content }
    }
}
