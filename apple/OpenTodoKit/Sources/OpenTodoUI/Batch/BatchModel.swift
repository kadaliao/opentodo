// What the batch actions (批量操作) work out before anything is written:
// the rules of `app/lib/ui/batch_actions.dart` as values and pure
// functions, so the panel and the bar only show them and report what the
// person chose (`BatchAction`), and the caller does the writing.

import Foundation
import OpenTodoDomain

/// What the person did with the picked tasks. Each case is one operation,
/// already worked out per task: the caller runs it through `TaskRepo` one
/// task at a time (as the Dart version does, so sync goes row by row),
/// and shows the undo toast where the Dart version did (完成, 删除).
public enum BatchAction: Hashable, Sendable {
    /// `TaskRepo.setDue(id, date, time)` for each: a new day (nil: 清除日期),
    /// each task keeping its own time.
    case setDue([BatchDueChange])
    /// `TaskRepo.setPriority` for each.
    case setPriority(ids: [String], Priority)
    /// `TaskRepo.moveToList` for each.
    case moveToList(ids: [String], listId: String)
    /// `TaskRepo.setTags` for each task whose tags change (only those).
    case setTags([BatchTagChange])
    /// `TaskRepo.setCompleted(id, true)` for each open task; then clear the
    /// selection and offer 撤销 (「已完成 N 个任务」).
    case complete(ids: [String])
    /// `TaskRepo.setPinned(id, pinned)` for the open tasks that change.
    case setPinned(ids: [String], pinned: Bool)
    /// The titles are already on the pasteboard, one per line; say so
    /// (「已复制 N 个任务的标题」).
    case copiedTitles(count: Int)
    /// `TaskRepo.trashTask` for each; then clear the selection and offer
    /// 撤销 (`restoreTask`), 「已把 N 个任务移到垃圾桶」.
    case trash(ids: [String])
    /// 取消 / 取消选择 (and Esc).
    case clearSelection
    /// 全选 (the bar's 更多 menu): pick every task of the view.
    case selectAll
}

public struct BatchDueChange: Hashable, Sendable {
    public let id: String
    public let date: Day?
    public let time: Int?

    public init(id: String, date: Day?, time: Int?) {
        self.id = id
        self.date = date
        self.time = time
    }
}

public struct BatchTagChange: Hashable, Sendable {
    public let id: String
    public let tags: [String]

    public init(id: String, tags: [String]) {
        self.id = id
        self.tags = tags
    }
}

/// The date menu: 今天, 明天, 下周一, 选择日期…, 清除日期.
public enum BatchDateChoice: String, CaseIterable, Hashable, Sendable {
    case today, tomorrow, nextWeek, pick, clear

    public var title: String {
        switch self {
        case .today: "今天"
        case .tomorrow: "明天"
        case .nextWeek: "下周一"
        case .pick: "选择日期…"
        case .clear: "清除日期"
        }
    }

    public var symbol: String {
        switch self {
        case .today: "sun.max"
        case .tomorrow: "sunrise"
        case .nextWeek: "calendar.badge.plus"
        case .pick: "calendar"
        case .clear: "calendar.badge.minus"
        }
    }

    /// The day it stands for; nil for 清除日期 (and for 选择日期…, which asks).
    public func day(today: Day) -> Day? {
        switch self {
        case .today: today
        case .tomorrow: today + 1
        case .nextWeek: today.startOfWeek + 7
        case .pick, .clear: nil
        }
    }
}

/// The picked tasks and what the panel says about them.
public struct BatchSelection: Hashable, Sendable {
    /// How many are picked (the header's 已选择 N 项): the selection's
    /// ids, even any whose task has just gone.
    public let count: Int
    /// The picked tasks that still exist and aren't in the trash, in the
    /// order given.
    public let tasks: [TodoTask]

    /// `ids`: the selection; `tasks`: the tasks the caller has (any order,
    /// any superset).
    public init(ids: Set<String>, tasks: [TodoTask]) {
        count = ids.count
        self.tasks = tasks.filter { ids.contains($0.id) && $0.trashedAt == nil }
    }

    public var ids: [String] { tasks.map(\.id) }

    /// The ones not yet done: 完成 and 置顶 only touch these.
    public var open: [TodoTask] { tasks.filter(isOpen) }

    // MARK: What the panel shows

    /// The one priority they share, nil when they differ.
    public var priority: Priority? {
        let ps = Set(tasks.map(\.priority))
        return ps.count == 1 ? ps.first : nil
    }

    /// 高优先级 … / 多种优先级.
    public var priorityTitle: String { priority.map(priorityName) ?? "多种优先级" }

    /// The lists they're in.
    public var listIds: Set<String> { Set(tasks.map(\.listId)) }

    /// The one list they share: the move menu ticks it.
    public var listId: String? { listIds.count == 1 ? listIds.first : nil }

    /// 工作 / 3 个清单.
    public func listTitle(_ lists: [String: TaskList]) -> String {
        listId.map { listName($0, lists) } ?? "\(listIds.count) 个清单"
    }

    /// Every tag any of them has, each once, in the order met.
    public var tags: [String] {
        var seen = Set<String>(), out: [String] = []
        for t in tasks { for tag in t.tags where seen.insert(tag).inserted { out.append(tag) } }
        return out
    }

    /// Every open one is pinned: the button says 取消置顶.
    public var allPinned: Bool { !open.isEmpty && open.allSatisfy { $0.pinnedAt != nil } }

    // MARK: Operations

    public func setDue(_ day: Day?) -> BatchAction {
        .setDue(tasks.map { BatchDueChange(id: $0.id, date: day, time: $0.dueTime) })
    }

    public func setPriority(_ p: Priority) -> BatchAction { .setPriority(ids: ids, p) }

    public func move(to listId: String) -> BatchAction { .moveToList(ids: ids, listId: listId) }

    public var complete: BatchAction { .complete(ids: open.map(\.id)) }

    /// 有没置顶的就全置顶，否则全取消: pin them all if any open one isn't,
    /// else unpin them all; only the ones that change.
    public var togglePin: BatchAction {
        let open = self.open
        let pin = open.contains { $0.pinnedAt == nil }
        return .setPinned(ids: open.filter { ($0.pinnedAt == nil) == pin }.map(\.id), pinned: pin)
    }

    /// One title per line, for the pasteboard.
    public var titlesText: String { tasks.map(\.title).joined(separator: "\n") }

    public var trash: BatchAction { .trash(ids: ids) }
}

/// Tags for several tasks at once (the Dart `_TagsDialog`): a tick means
/// all have it, a dash some, nothing none. Ticking adds a tag to all,
/// unticking takes it off all.
public struct BatchTagsEditor: Hashable, Sendable {
    public let tasks: [TodoTask]
    /// The app's tags (`known`), then any typed here.
    public private(set) var tags: [String]
    private var add: [String] = []
    private var remove: Set<String> = []

    public init(tasks: [TodoTask], known: [String]) {
        self.tasks = tasks
        tags = known
    }

    /// true: all have it; nil: some; false: none.
    public func state(_ tag: String) -> Bool? {
        if add.contains(tag) { return true }
        if remove.contains(tag) { return false }
        let n = tasks.count { $0.tags.contains(tag) }
        return n == 0 ? false : (n == tasks.count ? true : nil)
    }

    public mutating func toggle(_ tag: String) {
        if state(tag) == true {
            add.removeAll { $0 == tag }
            remove.insert(tag)
        } else {
            remove.remove(tag)
            if !add.contains(tag) { add.append(tag) }
        }
    }

    /// A tag typed in (leading #s dropped), ticked. False if there was nothing.
    @discardableResult
    public mutating func addNew(_ text: String) -> Bool {
        var tag = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        while tag.hasPrefix("#") { tag = tag.dropFirst() }
        guard !tag.isEmpty else { return false }
        let t = String(tag)
        if !tags.contains(t) { tags.append(t) }
        remove.remove(t)
        if !add.contains(t) { add.append(t) }
        return true
    }

    /// What 确定 writes: each task's tags without the removed ones, then
    /// the added ones it hasn't got; only tasks that change.
    public var changes: [BatchTagChange] {
        tasks.compactMap { t in
            let tags = t.tags.filter { !remove.contains($0) } + add.filter { !t.tags.contains($0) }
            return tags == t.tags ? nil : BatchTagChange(id: t.id, tags: tags)
        }
    }

    public var action: BatchAction { .setTags(changes) }
}

