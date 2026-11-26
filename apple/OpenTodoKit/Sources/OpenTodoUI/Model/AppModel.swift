// The state of one window: where we are (module, view, open task, layout
// width), the data (the latest `TaskData` snapshot from the database) and
// the clock, plus one sub-model per feature, each in its own file:
//
//     model.selection   SelectionModel  tasks picked together (多选)
//     model.notices     Notices         the undo banner (and ⌘Z)
//     model.present     Presentation    dialogs and sheets to show
//     model.search      SearchState     the search field
//     model.taskList    TaskListState   folded groups, 显示已完成, quick add focus
//
// A new feature adds its own `@Observable` class in its own file and one
// `let` here, so features don't step on each other.
//
// Reading: views take `@Environment(AppModel.self)` and use the derived
// values below (`sections(for:)`, `count(of:)`, `task(_:)` …): plain
// functions of `data` and `now`, recomputed when either changes.
// Writing: `model.repo` (TaskRepo) directly, or the actions in
// `AppModel+Actions.swift` where a write also shows something (an undo, a
// note). Changes come back through the observation; nothing is refreshed
// by hand.

import Foundation
import Observation
import OpenTodoData
import OpenTodoDomain
import SwiftUI

/// How much room the window has: one column (iPhone, a narrow iPad window)
/// or several side by side.
public enum WidthClass: Sendable, Hashable {
    case compact, regular
}

/// A screen pushed in the one-column (phone) layout: the tasks module's
/// `NavigationStack` path is a list of these.
public enum PhoneRoute: Sendable, Hashable {
    case view(ViewRef)
    case task(String)
}

@Observable
public final class AppModel {
    // MARK: Services

    /// Everything the app runs on (reminders, sync, the efficiency repo …),
    /// shared by all windows; nil in tests that make a model on a bare repo.
    public let services: AppServices?
    public let database: AppDatabase
    /// Every write goes through here.
    public let repo: TaskRepo
    /// Settings and per-view preferences (grouping, sort, layout), kept in
    /// `key_values`.
    public let settings: LocalSettings

    // MARK: Feature state

    public let selection = SelectionModel()
    public let notices = Notices()
    public let present = Presentation()
    public let search = SearchState()
    public let taskList = TaskListState()
    public let calendar = CalendarModel(anchor: .today())
    /// Habits, focus, countdowns, the matrix (Efficiency/App/EfficiencyModel.swift).
    public let efficiency = EfficiencyModel()

    // MARK: Where we are

    public var module: AppModule = .tasks
    /// The sidebar's selection.
    public private(set) var view: ViewRef = .smart(.today)
    public var width: WidthClass = .regular
    /// The tasks module's navigation stack in the compact layout.
    public var phonePath: [PhoneRoute] = []

    /// The task open in the detail (or pushed on a phone).
    public var selectedTaskId: String?

    // MARK: Data

    public private(set) var data: TaskData = .empty
    /// Whether the first snapshot has come in.
    public private(set) var loaded = false
    /// The wall clock, a minute at a time. Tests set it; `start()` keeps it
    /// current.
    public var now: LocalDateTime
    public var today: Day { now.day }
    public var timeZone: TimeZone { repo.timeZone }

    /// Values worked out from `data` (and `now`), kept until they change.
    @ObservationIgnored let derived = DerivedCache()
    @ObservationIgnored private var pendingRoute: DebugRoute?
    /// Whether a view was picked (by the person or a route) rather than
    /// being the default: a phone then opens straight into it.
    @ObservationIgnored private var viewPicked = false
    @ObservationIgnored private var started = false
    /// Started but still preparing (seeding) or waiting for its first
    /// snapshot: snapshots from outside must wait for its own.
    var awaitingFirstSnapshot: Bool { started && !loaded }
    @ObservationIgnored private var observation: ObservationHandle?
    /// Run once before the data is watched (seeding the database).
    @ObservationIgnored private var prepare: (() async -> Void)?

    public init(repo: TaskRepo, settings: LocalSettings? = nil, services: AppServices? = nil,
                now: LocalDateTime? = nil, prepare: (() async -> Void)? = nil) {
        self.services = services
        self.database = repo.database
        self.repo = repo
        self.settings = settings ?? LocalSettings(repo.database)
        self.now = now ?? LocalDateTime.now(in: repo.timeZone)
        self.prepare = prepare
    }

    /// Prepares the database, starts watching it and keeps `now` current.
    /// Idempotent; the root view calls it in `.task`.
    public func start(clock: Bool = true) async {
        guard !started else { return }
        started = true
        if let prepare {
            self.prepare = nil
            await prepare()
        }
        observation = database.observeTaskData().start(onError: { [weak self] error in
            self?.notices.show("读取数据出错：\(error.localizedDescription)")
        }, onChange: { [weak self] data in
            self?.receive(data)
        })
        guard clock else { return }
        Task { [weak self] in
            while !Task.isCancelled {
                let seconds = 60 - Calendar.current.component(.second, from: .now)
                try? await Task.sleep(for: .seconds(seconds) + .milliseconds(50))
                guard let self else { return }
                let current = LocalDateTime.now(in: self.timeZone)
                if current != self.now { self.now = current }
            }
        }
    }

    /// Takes in a new snapshot. Public for tests, which can feed data
    /// without a database.
    public func receive(_ snapshot: TaskData) {
        derived.clear()
        data = snapshot
        loaded = true
        if let route = pendingRoute {
            pendingRoute = nil
            apply(route)
        }
        if let id = selectedTaskId, task(id) == nil { selectedTaskId = nil }
        // A filter deleted elsewhere while on screen.
        if case .filter(let id) = view, filtersById[id] == nil { select(.smart(.today)) }
        if case .list(let id) = view, listsById[id] == nil { select(.smart(.inbox)) }
    }

    // MARK: Derived

    public var lists: [TaskList] { data.lists }
    public var listsById: [String: TaskList] {
        let d = data
        return derived.memo(\.listsById) { Dictionary(d.lists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    }
    public var filters: [TaskFilter] { data.filters }
    public var filtersById: [String: TaskFilter] {
        let d = data
        return derived.memo(\.filtersById) { Dictionary(d.filters.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    }
    /// Each saved filter's rule, read from its JSON.
    public var filterRules: [String: FilterRule] {
        let d = data
        return derived.memo(\.filterRules) {
            Dictionary(d.filters.map { ($0.id, FilterRule.parse($0.rule)) }, uniquingKeysWith: { a, _ in a })
        }
    }
    public var sectionsByList: [String: [ListSection]] {
        let d = data
        return derived.memo(\.sectionsByList) { Dictionary(grouping: d.sections, by: \.listId) }
    }

    /// Every tag on a task that isn't in the trash, sorted (`tagsProvider`).
    public var tags: [String] {
        let d = data
        return derived.memo(\.tags) { Set(d.tasks.filter { $0.trashedAt == nil }.flatMap(\.tags)).sorted() }
    }

    public func task(_ id: String) -> TodoTask? {
        let d = data
        return derived.memo(\.tasksById) { Dictionary(d.tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }[id]
    }

    public var selectedTask: TodoTask? { selectedTaskId.flatMap(task) }

    public func checklist(of taskId: String) -> [ChecklistItem] { checklistsByTask[taskId] ?? [] }

    /// Every task's checklist, in the snapshot's order.
    var checklistsByTask: [String: [ChecklistItem]] {
        let d = data
        return derived.memo(\.checklists) { Dictionary(grouping: d.checklistItems, by: \.taskId) }
    }

    /// (done, all) of a task's checklist, for the row's 2/5.
    public func checklistProgress(of taskId: String) -> (done: Int, total: Int) {
        let items = checklist(of: taskId)
        return (items.count(where: \.done), items.count)
    }

    public func title(of view: ViewRef) -> String { viewTitle(view, listsById, filtersById) }

    /// The number beside a view in the sidebar: its open tasks.
    public func count(of view: ViewRef) -> Int {
        let tasks = data.tasks
        let now = self.now
        derived.clocked(at: now)
        // All of them at once: the sidebar asks for every view's.
        if derived.counts == nil { derived.counts = openCounts(tasks, now, filterRules) }
        return derived.counts![view]
    }

    /// How `view` is shown on this device (layout, grouping, sort).
    public func prefs(for view: ViewRef) -> ViewPrefs { settings.viewPrefs(for: view) }

    /// `view`'s groups of tasks, as its grouping and sort say; without
    /// 已完成 when the person hid it.
    public func sections(for view: ViewRef) -> [TaskSection] {
        let p = prefs(for: view)
        let showsDone = taskList.showsDone(view)
        let tasks = data.tasks
        let now = self.now
        derived.clocked(at: now)
        let key = DerivedCache.SectionsKey(view: view, prefs: p, showsDone: showsDone)
        if let cached = derived.sections[key] { return cached }
        var out = buildSections(view: view, tasks: tasks, lists: listsById, now: now, filters: filterRules,
                                sectionsByList: sectionsByList, grouping: p.grouping, sort: p.sort, timeZone: timeZone)
        if !showsDone { out = out.filter { !($0.finished && $0.id == "done") } }
        derived.sections[key] = out
        return out
    }

    /// Whether rows in `view` name their list: views that gather several
    /// lists, unless the groups already are lists.
    public func showsList(in view: ViewRef) -> Bool {
        switch view {
        case .smart, .tag, .filter: prefs(for: view).groupingIn(view) != .list
        case .list: false
        }
    }

    // MARK: Navigation

    /// Shows `view` (what the sidebar does). Picking another view closes the
    /// open task, as in the Flutter version.
    public func select(_ view: ViewRef) {
        if view != self.view {
            self.view = view
            selectedTaskId = nil
            selection.clear()
        }
        viewPicked = true
        if width == .compact { phonePath = [.view(view)] }
    }

    /// Opens a task in the current view (what a row does).
    public func open(taskId: String) {
        selectedTaskId = taskId
        guard width == .compact else { return }
        let base = phonePath.filter { if case .view = $0 { true } else { false } }
        phonePath = base + [.task(taskId)]
    }

    /// Shows a task from anywhere — search, the calendar, a notification:
    /// in the current view if it lists the task, else where it belongs
    /// (`viewForTask`), switching to the tasks module.
    public func revealTask(_ id: String) {
        guard let t = task(id) else {
            if !loaded { pendingRoute = .task(id) }
            return
        }
        switchTo(.tasks)
        select(viewForTask(t, view, now, filterRules))
        open(taskId: id)
    }

    /// Moves to the layout of `width`, keeping what's open.
    public func setWidth(_ width: WidthClass) {
        guard width != self.width else { return }
        self.width = width
        if width == .compact {
            phonePath = (viewPicked ? [.view(view)] : []) + (selectedTaskId.map { [.task($0)] } ?? [])
        }
    }

    /// Keeps `view` / the open task in step with the phone's stack when the
    /// person goes back.
    public func phonePathChanged() {
        var v: ViewRef?
        var t: String?
        for r in phonePath {
            switch r {
            case .view(let x): v = x
            case .task(let x): t = x
            }
        }
        // Another view starts picking afresh (as `select`, and Flutter's TaskSelection).
        if let v, v != view { self.view = v; viewPicked = true; selection.clear() }
        if t != selectedTaskId { selectedTaskId = t }
    }

    /// Changes module. As in the Flutter version this drops the picked
    /// tasks and closes the open one — on a wide window; a phone keeps each
    /// tab's own pages.
    public func switchTo(_ module: AppModule) {
        if module != self.module {
            selection.clear()
            if width == .regular { selectedTaskId = nil }
        }
        self.module = module
    }

    /// 新建任务 (⌘N): focus the field heading the list or timeline, or the
    /// sheet on a phone and on a board (whose columns have their own fields).
    public func requestQuickAdd() {
        switchTo(.tasks)
        if width == .compact || prefs(for: view).layoutIn(view) == .board {
            present.quickAdd = true
        } else {
            taskList.focusQuickAdd()
        }
    }

    /// 搜索 (⌘F).
    public func requestSearch() { search.focus() }

    /// Opens a `-OTOpen` route. Routes naming a task wait for the data.
    public func apply(_ route: DebugRoute) {
        switch route {
        case .home:
            break
        case .smart(let k):
            if let kind = SmartKind(rawValue: k) { switchTo(.tasks); select(.smart(kind)) }
        case .list(let id):
            switchTo(.tasks); select(id == inboxListId ? .smart(.inbox) : .list(id))
        case .tag(let tag):
            switchTo(.tasks); select(.tag(tag))
        case .filter(let id):
            switchTo(.tasks); select(.filter(id))
        case .task(let id):
            revealTask(id)
        case .calendar(let mode):
            openCalendar(mode: mode)
        case .timeline:
            switchTo(.tasks)
            settings.setLayout(view, .timeline)
        case .settings:
            present.settings = true
        default:
            // Routes that open one feature's own screens (the schedule dialog,
            // the timeline…) are handled by that feature's debug presenter.
            break
        }
    }

    /// Shows what was opened from a notification (`ReminderController
    /// .openRequest`). Habits and countdowns are the efficiency modules'.
    public func handle(_ request: ReminderOpenRequest) {
        switch request {
        case .task(let id): revealTask(id)
        case .habit(let id): efficiency.open(.habits, detail: id, in: self)
        case .countdown(let id): efficiency.open(.countdowns, detail: id, in: self)
        }
    }

    /// Applies `route` once the first snapshot is in.
    public func applyWhenLoaded(_ route: DebugRoute) {
        if loaded { apply(route) } else { pendingRoute = route }
    }
}
