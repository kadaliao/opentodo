// Demo data for the board and the drag pieces (debug routes `board:<scene>`,
// screenshots), and a stand-in for TaskRepo that applies what the
// components report to it in memory, so the debug screens can be played
// with.

import OpenTodoDomain
import SwiftUI

@MainActor @Observable
final class BoardDemoStore {
    static let listId = "demo-list"
    static let now = LocalDateTime(Day(2026, 11, 26), minute: 10 * 60)

    var tasks: [TodoTask]
    var sections: [ListSection]
    var checklist: [ChecklistItem]
    var selection = BoardSelection()
    var sort: TaskSort = .manual
    private var next = 0

    init(empty: Bool = false) {
        let list = Self.listId
        let today = Self.now.day
        sections = [
            ListSection(id: "s-ideas", listId: list, name: "想法", sortOrder: 0),
            ListSection(id: "s-week", listId: list, name: "本周", sortOrder: 1024),
            ListSection(id: "s-doing", listId: list, name: "进行中", sortOrder: 2048),
            ListSection(id: "s-review", listId: list, name: "等反馈", sortOrder: 3072),
        ]
        guard !empty else {
            tasks = []
            checklist = []
            return
        }
        func t(
            _ id: String, _ title: String, _ section: String?, _ order: Double,
            due: Day? = nil, time: Int? = nil, priority: Priority = .none, tags: [String] = [],
            reminders: [Int] = [], repeating: Bool = false, pinned: Bool = false, done: Int? = nil
        ) -> TodoTask {
            TodoTask(
                id: id, listId: list, sectionId: section, title: title, priority: priority,
                dueDate: due, dueTime: time, tags: tags, status: done == nil ? .open : .done,
                completedAt: done, reminders: reminders, repeatRule: repeating ? "FREQ=WEEKLY" : nil,
                pinnedAt: pinned ? 1 : nil, sortOrder: order, createdAt: Int(order)
            )
        }
        tasks = [
            t("t1", "首页改版的三个方向", "s-ideas", 0, tags: ["设计"]),
            t("t2", "竞品的看板怎么处理已完成", "s-ideas", 1024),
            t("t3", "整理用户访谈记录", "s-ideas", 2048, priority: .low, tags: ["调研"]),
            t("t4", "发布说明初稿", "s-week", 0, due: today, time: 15 * 60, priority: .high, reminders: [0], pinned: true),
            t("t5", "更新应用截图", "s-week", 1024, due: today + 1, priority: .medium, tags: ["设计", "发布"]),
            t("t6", "周会", "s-week", 2048, due: today + 4, time: 10 * 60, reminders: [-15], repeating: true),
            t("t7", "准备 TestFlight 测试组", "s-week", 3072, due: today - 1, priority: .high),
            t("t8", "同步冲突的边角情况", "s-doing", 0, priority: .high, tags: ["同步"]),
            t("t9", "看板拖动：自动滚动和落点提示线，iPhone 上长按以后拖", "s-doing", 1024, due: today + 2),
            t("t10", "隐私说明页", "s-review", 0, due: today + 8, priority: .low),
            t("t11", "收集反馈的表单", nil, 0),
            t("d1", "注册开发者账号", "s-week", 0, done: 3),
            t("d2", "图标定稿", "s-doing", 0, tags: ["设计"], done: 2),
            t("d3", "确定发布日期", "s-doing", 0, done: 1),
        ]
        checklist = [
            ChecklistItem(id: "c1", taskId: "t4", title: "新功能", done: true),
            ChecklistItem(id: "c2", taskId: "t4", title: "修复", done: true),
            ChecklistItem(id: "c3", taskId: "t4", title: "致谢"),
            ChecklistItem(id: "c4", taskId: "t9", title: "落点"),
            ChecklistItem(id: "c5", taskId: "t9", title: "滚动"),
        ]
    }

    var columns: [BoardColumn] { boardColumns(Self.listId, tasks, sections, sort: sort) }

    var actions: BoardActions {
        BoardActions(
            tap: { [weak self] id, modifiers in self?.tap(id, modifiers) },
            setDone: { [weak self] task, done in self?.setDone(task.id, done) },
            quickAdd: { [weak self] q in self?.add(q.text, sectionId: q.sectionId) },
            drop: { [weak self] plan in self?.apply(plan) },
            section: { [weak self] action in self?.apply(action) }
        )
    }

    func tap(_ id: String, _ modifiers: EventModifiers) {
        if modifiers.contains(.command) {
            var picked = selection.picked
            if picked.isEmpty, let open = selection.open { picked.insert(open) }
            if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
            selection = BoardSelection(open: selection.open, picked: picked)
        } else {
            selection = BoardSelection(open: id)
        }
    }

    func setDone(_ id: String, _ done: Bool) {
        update(id) {
            $0.status = done ? .done : .open
            $0.completedAt = done ? 100 + self.tasks.count : nil
        }
    }

    func add(_ title: String, sectionId: String?) {
        next += 1
        let last = tasks.filter { $0.sectionId == sectionId }.map(\.sortOrder).max() ?? 0
        tasks.append(TodoTask(id: "new\(next)", listId: Self.listId, sectionId: sectionId, title: title, sortOrder: last + orderStep))
    }

    /// What `TaskRepo.dropInto` does.
    func apply(_ plan: TaskDropPlan) {
        for id in plan.ids {
            guard let t = tasks.first(where: { $0.id == id }), !plan.target.has(t) else { continue }
            update(id) { t in
                switch plan.target {
                case .section(_, let sectionId): t.sectionId = sectionId
                case .date(let day): t.dueDate = day
                    if day == nil { t.dueTime = nil }
                case .priority(let p): t.priority = p
                case .list(let listId): t.listId = listId
                    t.sectionId = nil
                case .tag: t.tags = plan.target.retag(t.tags)
                case .order: break
                }
            }
        }
        for (id, order) in plan.orders { update(id) { $0.sortOrder = order } }
    }

    func apply(_ action: SectionAction) {
        switch action {
        case let .add(listId, name):
            next += 1
            sections.append(ListSection(
                id: "s-new\(next)", listId: listId, name: name, sortOrder: (sections.map(\.sortOrder).max() ?? 0) + orderStep
            ))
        case let .rename(id, name):
            if let i = sections.firstIndex(where: { $0.id == id }) { sections[i].name = name }
        case .reorder(let orders):
            for (id, order) in orders {
                if let i = sections.firstIndex(where: { $0.id == id }) { sections[i].sortOrder = order }
            }
        case .delete(let id):
            sections.removeAll { $0.id == id }
            for i in tasks.indices where tasks[i].sectionId == id { tasks[i].sectionId = nil }
        }
    }

    private func update(_ id: String, _ change: (inout TodoTask) -> Void) {
        if let i = tasks.firstIndex(where: { $0.id == id }) { change(&tasks[i]) }
    }
}

/// The board on demo data, in the states the debug route `board:<scene>`
/// names.
struct BoardDemo: View {
    enum Scene: String, CaseIterable {
        /// Manual order, a pinned card, dates, tags, checklist progress.
        case manual
        /// Two cards picked (多选).
        case picked
        /// Ordered by priority: drops only change section.
        case priority
        /// A column's field open, finished cards shown.
        case adding
        /// A list with sections and nothing in them.
        case empty
        /// The section dialogs.
        case add, rename, delete
        /// A drag hovering: the insertion line between cards…
        case line
        /// …a whole column lit up (by priority)…
        case group
        /// …a column dragged between two others.
        case section
        /// The dragged copies: one card, and three together.
        case preview
        /// The drag pieces in a plain grouped list (DragListDemo).
        case list
    }

    let scene: Scene
    @State private var store: BoardDemoStore
    @State private var drag = DragController()
    @State private var dialog: SectionDialog?

    init(scene: Scene) {
        self.scene = scene
        let store = BoardDemoStore(empty: scene == .empty)
        switch scene {
        case .picked: store.selection = BoardSelection(open: "t5", picked: ["t5", "t8"])
        case .priority, .group: store.sort = .priority
        default: store.selection = BoardSelection(open: "t5")
        }
        _store = State(initialValue: store)
    }

    var body: some View {
        switch scene {
        case .list: DragListDemo()
        case .preview: previews
        default: board
        }
    }

    private var board: some View {
        NavigationStack {
            BoardView(
                listId: BoardDemoStore.listId,
                columns: store.columns,
                sort: store.sort,
                now: BoardDemoStore.now,
                selection: store.selection,
                progress: ChecklistProgress.of(store.checklist),
                actions: store.actions,
                drag: drag
            ) { task in
                Button("置顶", systemImage: "pin") {}
                Button("删除", systemImage: "trash", role: .destructive) {}
                    .disabled(task.status != .open)
            }
            .environment(\.boardStart, BoardStart(adding: scene == .adding ? "s-week" : nil, showDone: scene == .adding))
            .navigationTitle("产品发布")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem {
                    Menu {
                        Picker("排序", selection: $store.sort) {
                            ForEach(TaskSort.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                    } label: {
                        Label("分组和排序", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .sectionDialogs($dialog, perform: store.actions.section)
        .task { await stage() }
    }

    /// Puts the scene's dialog up or its drag in the air once the board has
    /// been laid out.
    private func stage() async {
        try? await Task.sleep(for: .milliseconds(500))
        let s = store.sections
        switch scene {
        case .add: dialog = .add(listId: BoardDemoStore.listId)
        case .rename: dialog = .rename(s[1])
        case .delete: dialog = .delete(s[2])
        case .line:
            let lead = store.tasks.first { $0.id == "t3" }!
            hover(.tasks(DraggedTasks(lead)), over: "row-t9", fraction: 0.85)
        case .group:
            let lead = store.tasks.first { $0.id == "t2" }!
            hover(.tasks(DraggedTasks(lead)), over: "row-t8", fraction: 0.3)
        case .section:
            hover(.section(s[3]), over: "column-s-week", fraction: 0.5, x: 0.25)
        default: break
        }
    }

    private func hover(_ item: DragItem, over slot: String, fraction: CGFloat, x: CGFloat = 0.5) {
        guard let f = drag.visibleSlots.first(where: { $0.id == slot })?.frame else { return }
        drag.begin(item)
        drag.move(to: CGPoint(x: f.minX + f.width * x, y: f.minY + f.height * fraction))
    }

    private var previews: some View {
        let tasks = store.tasks
        return HStack(alignment: .top, spacing: 40) {
            DragStackPreview(count: 1) {
                BoardCard(task: tasks[4], selected: false, now: BoardDemoStore.now, progress: nil) {}.frame(width: 256)
            }
            DragStackPreview(count: 3) {
                BoardCard(task: tasks[3], selected: false, now: BoardDemoStore.now,
                          progress: ChecklistProgress(done: 2, total: 3)) {}.frame(width: 256)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BoardStyle.boardBackground)
    }
}

/// Debug route `board:<scene>`: the board demo in place of the app. And
/// `board:@<list id>[/<task id>]`: the app with that list as a board (and
/// the task open), on whatever data the app has (`-OTSeed demo`).
struct BoardDebugPresenter: ViewModifier {
    let route: DebugRoute?
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if case .board(let name)? = route, let scene = BoardDemo.Scene(rawValue: name) {
            BoardDemo(scene: scene)
        } else if case .board(let name)? = route, name.hasPrefix("@") {
            content.task {
                let parts = name.dropFirst().split(separator: "/").map(String.init)
                guard let listId = parts.first else { return }
                let view: ViewRef = listId == inboxListId ? .smart(.inbox) : .list(listId)
                model.settings.setLayout(view, .board)
                model.applyWhenLoaded(.list(listId))
                if parts.count > 1 {
                    while !model.loaded { try? await Task.sleep(for: .milliseconds(50)) }
                    model.open(taskId: parts[1])
                }
            }
        } else {
            content
        }
    }
}
