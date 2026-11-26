// 四象限: the module's root. Four blocks, each a quadrant's open tasks
// (pinned first, then by date). On a wide window each block is a full list
// with its own quick-add field; on a phone the four are small and a tap on
// one opens it as a page. Tasks are dragged between blocks (or moved with
// the context menu, which also works on a phone).
//
// A self-contained component: it gets the tasks, the quadrants' settings
// and now; it hands back what the person did. `onMoveTask` gives the task
// as it was and as it should be saved (the list, date, tag or priority the
// target quadrant asks for); `onQuickAdd` the title typed into a quadrant
// and where the new task goes. The rule editor is a slot: `ruleEditor`
// gets a quadrant and a callback, and returns the editor to show in a sheet
// (the app passes the filter editor); without it each quadrant's rule is
// edited inline as a choice of priorities.
//
//     MatrixRootView(tasks: tasks, prefs: prefs, now: now, lists: lists,
//                    onToggleDone: repo.toggleDone, onOpenTask: open,
//                    onMoveTask: { _, new in repo.save(new) },
//                    onQuickAdd: repo.quickAdd, onPrefsChange: store.saveMatrix)

import OpenTodoDomain
import SwiftUI

public struct MatrixRootView: View {
    public var tasks: [TodoTask]
    public var prefs: MatrixPrefs
    public var now: LocalDateTime
    public var lists: [TaskList]
    public var onToggleDone: (TodoTask) -> Void
    public var onOpenTask: (TodoTask) -> Void
    public var onMoveTask: (TodoTask, TodoTask) -> Void
    public var onQuickAdd: (String, QuickAddDefaults) -> Void
    public var onPrefsChange: (MatrixPrefs) -> Void
    public var ruleEditor: MatrixRuleEditor?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path: [Int]
    @State private var editing: Bool

    public init(
        tasks: [TodoTask],
        prefs: MatrixPrefs,
        now: LocalDateTime,
        lists: [TaskList] = [],
        onToggleDone: @escaping (TodoTask) -> Void,
        onOpenTask: @escaping (TodoTask) -> Void,
        onMoveTask: @escaping (TodoTask, TodoTask) -> Void,
        onQuickAdd: @escaping (String, QuickAddDefaults) -> Void,
        onPrefsChange: @escaping (MatrixPrefs) -> Void,
        ruleEditor: MatrixRuleEditor? = nil
    ) {
        self.init(tasks: tasks, prefs: prefs, now: now, lists: lists, onToggleDone: onToggleDone, onOpenTask: onOpenTask,
                  onMoveTask: onMoveTask, onQuickAdd: onQuickAdd, onPrefsChange: onPrefsChange, ruleEditor: ruleEditor,
                  start: .grid)
    }

    enum Start: Hashable {
        case grid
        case quadrant(Int)
        case edit
    }

    init(
        tasks: [TodoTask], prefs: MatrixPrefs, now: LocalDateTime, lists: [TaskList],
        onToggleDone: @escaping (TodoTask) -> Void, onOpenTask: @escaping (TodoTask) -> Void,
        onMoveTask: @escaping (TodoTask, TodoTask) -> Void, onQuickAdd: @escaping (String, QuickAddDefaults) -> Void,
        onPrefsChange: @escaping (MatrixPrefs) -> Void, ruleEditor: MatrixRuleEditor?, start: Start
    ) {
        self.tasks = tasks
        self.prefs = prefs
        self.now = now
        self.lists = lists
        self.onToggleDone = onToggleDone
        self.onOpenTask = onOpenTask
        self.onMoveTask = onMoveTask
        self.onQuickAdd = onQuickAdd
        self.onPrefsChange = onPrefsChange
        self.ruleEditor = ruleEditor
        if case .quadrant(let i) = start { _path = State(initialValue: [i]) } else { _path = State(initialValue: []) }
        _editing = State(initialValue: start == .edit)
    }

    private var compact: Bool { sizeClass == .compact }

    public var body: some View {
        let cells = matrixCells(tasks, prefs: prefs, now: now)
        NavigationStack(path: $path) {
            Grid(horizontalSpacing: compact ? 10 : 14, verticalSpacing: compact ? 10 : 14) {
                GridRow {
                    block(cells[0])
                    block(cells[1])
                }
                GridRow {
                    block(cells[2])
                    block(cells[3])
                }
            }
            .padding(compact ? 12 : 16)
            .background(Color.groupedBackground)
            .navigationTitle("四象限")
            .efficiencyTitleMenu()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("编辑象限", systemImage: "slider.horizontal.3") { editing = true }
                }
            }
            .navigationDestination(for: Int.self) { i in
                MatrixQuadrantPage(
                    cell: matrixCells(tasks, prefs: prefs, now: now)[i], prefs: prefs, now: now, lists: lists,
                    actions: actions
                )
            }
        }
        .sheet(isPresented: $editing) {
            MatrixEditView(prefs: prefs, onSave: onPrefsChange, ruleEditor: ruleEditor)
        }
    }

    private var actions: MatrixRowActions {
        MatrixRowActions(
            toggleDone: onToggleDone,
            open: onOpenTask,
            move: { id, i in
                if let (old, new) = matrixDrop(taskId: id, into: i, tasks: tasks, prefs: prefs, now: now) { onMoveTask(old, new) }
            },
            quickAdd: { title, i in
                onQuickAdd(title, matrixQuickAddDefaults(i, prefs: prefs, today: now.day))
            }
        )
    }

    private func block(_ cell: MatrixCell) -> some View {
        MatrixBlock(
            cell: cell, prefs: prefs, now: now, lists: lists, compact: compact, actions: actions,
            onExpand: { path.append(cell.index) }
        )
    }
}

/// Returns the editor for one quadrant (shown in a sheet); it calls the
/// callback with the quadrant as edited (name and rule) and dismisses itself.
public typealias MatrixRuleEditor = (MatrixQuadrant, @escaping (MatrixQuadrant) -> Void) -> AnyView

/// What the rows and blocks can ask for.
struct MatrixRowActions {
    var toggleDone: (TodoTask) -> Void
    var open: (TodoTask) -> Void
    /// A task id dropped into a quadrant.
    var move: (String, Int) -> Void
    var quickAdd: (String, Int) -> Void
}

// MARK: - Block

struct MatrixBlock: View {
    var cell: MatrixCell
    var prefs: MatrixPrefs
    var now: LocalDateTime
    var lists: [TaskList]
    var compact: Bool
    var actions: MatrixRowActions
    var onExpand: () -> Void

    @State private var targeted = false
    @State private var newTitle = ""

    private var tint: Color { MatrixStyle.tint(cell.index) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onExpand) {
                HStack(spacing: 6) {
                    Image(systemName: MatrixStyle.symbol(cell.index)).foregroundStyle(tint)
                    Text(cell.name).font(compact ? .subheadline.weight(.semibold) : .headline).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(cell.tasks.count)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.top, compact ? 10 : 12)
            .padding(.bottom, 6)
            .accessibilityLabel(Text("\(cell.name)，\(cell.tasks.count)个任务"))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(cell.tasks) { t in
                        MatrixTaskRow(task: t, now: now, lists: lists, compact: compact, tint: tint,
                                      onToggle: compact ? nil : { actions.toggleDone(t) })
                            .padding(.horizontal, compact ? 10 : 14)
                            .contentShape(.rect)
                            .onTapGesture { compact ? onExpand() : actions.open(t) }
                            .draggable(t.id) {
                                Text(t.title).padding(8).background(.regularMaterial, in: .rect(cornerRadius: 8))
                            }
                            .contextMenu { MatrixTaskMenu(task: t, index: cell.index, prefs: prefs, actions: actions) }
                    }
                    if cell.tasks.isEmpty {
                        Text(compact ? "没有任务" : "没有任务，可以把任务拖到这里")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, compact ? 10 : 14)
                            .padding(.vertical, 8)
                    }
                }
            }
            .scrollDisabled(compact)

            if !compact {
                HStack(spacing: 6) {
                    Image(systemName: "plus").foregroundStyle(tint)
                    TextField("添加任务", text: $newTitle)
                        .textFieldStyle(.plain)
                        .onSubmit(add)
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.cardBackground, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(tint, lineWidth: 2)
                .opacity(targeted ? 1 : 0)
        }
        .clipShape(.rect(cornerRadius: 14))
        .dropDestination(for: String.self) { ids, _ in
            for id in ids { actions.move(id, cell.index) }
            return !ids.isEmpty
        } isTargeted: { targeted = $0 }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        actions.quickAdd(title, cell.index)
        newTitle = ""
    }
}

struct MatrixTaskRow: View {
    var task: TodoTask
    var now: LocalDateTime
    var lists: [TaskList]
    var compact: Bool
    var tint: Color
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if let onToggle {
                    Button(action: onToggle) {
                        Image(systemName: "circle")
                            .font(.body)
                            .foregroundStyle(priorityTint(task.priority))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("完成"))
                } else {
                    Image(systemName: "circle")
                        .font(compact ? .caption : .body)
                        .foregroundStyle(priorityTint(task.priority))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title.isEmpty ? "无标题" : task.title)
                    .font(compact ? .footnote : .body)
                    .lineLimit(compact ? 1 : 2)
                if !compact, let line = detailLine {
                    Text(line.text)
                        .font(.caption)
                        .foregroundStyle(line.overdue ? Color.red : .secondary)
                }
            }
            Spacer(minLength: 0)
            if task.pinnedAt != nil {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, compact ? 3 : 6)
    }

    private var detailLine: (text: String, overdue: Bool)? {
        var parts: [String] = []
        if let d = task.dueDate { parts.append(dueLabel(d, task.dueTime, today: now.day, duration: task.duration)) }
        if task.listId != inboxListId, let l = lists.first(where: { $0.id == task.listId }) { parts.append(l.name) }
        return parts.isEmpty ? nil : (parts.joined(separator: " · "), isOverdue(task, now))
    }
}

/// A task's context menu: complete, open, move to another quadrant.
struct MatrixTaskMenu: View {
    var task: TodoTask
    var index: Int
    var prefs: MatrixPrefs
    var actions: MatrixRowActions

    var body: some View {
        Button("完成", systemImage: "checkmark.circle") { actions.toggleDone(task) }
        Button("打开", systemImage: "arrow.up.right.square") { actions.open(task) }
        Menu("移到", systemImage: "arrow.right.square") {
            ForEach(prefs.quadrants.indices, id: \.self) { i in
                if i != index {
                    Button(prefs.quadrants[i].name, systemImage: MatrixStyle.symbol(i)) { actions.move(task.id, i) }
                }
            }
        }
    }
}

// MARK: - Quadrant page

/// One quadrant as a whole page (a phone, or "show all").
struct MatrixQuadrantPage: View {
    var cell: MatrixCell
    var prefs: MatrixPrefs
    var now: LocalDateTime
    var lists: [TaskList]
    var actions: MatrixRowActions

    @State private var newTitle = ""

    var body: some View {
        let tint = MatrixStyle.tint(cell.index)
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(tint)
                    TextField("添加任务到“\(cell.name)”", text: $newTitle)
                        .onSubmit {
                            let title = newTitle.trimmingCharacters(in: .whitespaces)
                            guard !title.isEmpty else { return }
                            actions.quickAdd(title, cell.index)
                            newTitle = ""
                        }
                }
            }
            Section {
                if cell.tasks.isEmpty {
                    Text("没有任务").foregroundStyle(.secondary)
                }
                ForEach(cell.tasks) { t in
                    MatrixTaskRow(task: t, now: now, lists: lists, compact: false, tint: tint, onToggle: { actions.toggleDone(t) })
                        .contentShape(.rect)
                        .onTapGesture { actions.open(t) }
                        .swipeActions(edge: .leading) {
                            Button("完成", systemImage: "checkmark") { actions.toggleDone(t) }.tint(.green)
                        }
                        .contextMenu { MatrixTaskMenu(task: t, index: cell.index, prefs: prefs, actions: actions) }
                }
            }
        }
        .navigationTitle(cell.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Editing the quadrants

struct MatrixEditView: View {
    var prefs: MatrixPrefs
    var onSave: (MatrixPrefs) -> Void
    var ruleEditor: MatrixRuleEditor?

    @Environment(\.dismiss) private var dismiss
    @State private var names: [String]
    @State private var rules: [FilterRule]
    @State private var editingRule: Int?

    init(prefs: MatrixPrefs, onSave: @escaping (MatrixPrefs) -> Void, ruleEditor: MatrixRuleEditor?) {
        self.prefs = prefs
        self.onSave = onSave
        self.ruleEditor = ruleEditor
        _names = State(initialValue: prefs.quadrants.map(\.name))
        _rules = State(initialValue: prefs.quadrants.map(\.filterRule))
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(0..<4, id: \.self) { i in
                    Section {
                        TextField("名称", text: $names[i])
                        if ruleEditor != nil {
                            Button {
                                editingRule = i
                            } label: {
                                LabeledContent("条件", value: ruleSummary(rules[i]))
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        } else {
                            PriorityRuleEditor(rule: $rules[i])
                        }
                    } header: {
                        Label("象限\(i + 1)", systemImage: MatrixStyle.symbol(i)).foregroundStyle(MatrixStyle.tint(i))
                    } footer: {
                        Text(ruleSummary(rules[i]))
                    }
                }
                Section {
                    Button("恢复默认") {
                        names = MatrixPrefs.defaultQuadrants.map(\.name)
                        rules = MatrixPrefs.defaultQuadrants.map(\.filterRule)
                    }
                } footer: {
                    Text("一个任务符合几个象限时，放在排在前面的那个。")
                }
            }
            .formStyle(.grouped)
            .sheet(item: Binding(get: { editingRule.map(RuleIndex.init) }, set: { editingRule = $0?.id })) { r in
                if let ruleEditor {
                    ruleEditor(MatrixQuadrant(name: names[r.id], rule: rules[r.id])) { q in
                        let name = q.name.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty { names[r.id] = name }
                        rules[r.id] = q.filterRule
                    }
                }
            }
            .navigationTitle("编辑象限")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSave(MatrixPrefs(quadrants: (0..<4).map { i in
                            let name = names[i].trimmingCharacters(in: .whitespaces)
                            return MatrixQuadrant(name: name.isEmpty ? MatrixPrefs.defaultQuadrants[i].name : name, rule: rules[i])
                        }))
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }
}

private struct RuleIndex: Identifiable {
    var id: Int
}

/// The stand-in rule editor: which priorities the quadrant gathers.
struct PriorityRuleEditor: View {
    @Binding var rule: FilterRule

    var body: some View {
        let chosen = rulePriorities(rule)
        HStack {
            Text("优先级")
            Spacer()
            ForEach(priorityChoices, id: \.key) { c in
                let on = chosen.contains(c.priority)
                Button {
                    var s = chosen
                    if on { s.remove(c.priority) } else { s.insert(c.priority) }
                    rule = ruleWithPriorities(rule, s)
                } label: {
                    Text(c.label)
                        .font(.subheadline.weight(.medium))
                        .frame(width: 32, height: 28)
                        .background(on ? priorityTint(c.priority).opacity(0.9) : Color.secondary.opacity(0.12), in: .capsule)
                        .foregroundStyle(on ? Color.white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(c.label)优先级"))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
