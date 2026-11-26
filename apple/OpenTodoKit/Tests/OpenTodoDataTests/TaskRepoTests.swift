// Port of app/test/repo_test.dart, and the cases of sections_test,
// pin_sort_test, grouping_test and timeline_test that run through TaskRepo
// (the pure parts are in OpenTodoDomainTests).

import Foundation
import GRDB
import Synchronization
import Testing
@testable import OpenTodoData

/// A clock tests can move.
final class TestClock: Sendable {
    private let value: Mutex<Date>
    init(_ date: Date = LocalDateTime(2026, 11, 15, 10).date()) { value = Mutex(date) }
    var now: Date { value.withLock { $0 } }
    var ms: Int { nowMilliseconds(now) }
    func set(_ date: Date) { value.withLock { $0 = date } }
    func advance(minutes: Int = 0, seconds: Int = 0) { value.withLock { $0 += TimeInterval(minutes * 60 + seconds) } }
}

/// A box for defaults a test changes as it goes.
final class Defaults: Sendable {
    private let value: Mutex<TaskDefaults>
    init(_ d: TaskDefaults) { value = Mutex(d) }
    var current: TaskDefaults { value.withLock { $0 } }
    func set(_ d: TaskDefaults) { value.withLock { $0 = d } }
}

struct RepoFixture {
    let db: AppDatabase
    let clock: TestClock
    let repo: TaskRepo

    init(clock: TestClock = TestClock(), defaults: (@Sendable () -> TaskDefaults)? = nil) throws {
        db = try AppDatabase.inMemory()
        self.clock = clock
        repo = TaskRepo(db, clock: { clock.now }, defaults: defaults ?? { .standard })
    }

    func tasks() async throws -> [TodoTask] { try await db.observeTasks().first() }
    func sections() async throws -> [ListSection] { try await db.observeSections().first() }
    func checklist(_ id: String) async throws -> [ChecklistItem] { try await db.observeChecklist(taskId: id).first() }
    func task(_ id: String) async throws -> TodoTask { try #require(try await repo.getTask(id)) }
}

private let d1115 = Day(2026, 11, 15)
private let d1116 = Day(2026, 11, 16)

@Suite struct TaskRepoTests {
    let f: RepoFixture
    var repo: TaskRepo { f.repo }
    var clock: TestClock { f.clock }
    init() throws { f = try RepoFixture() }

    @Test("adding a task stores its date as a calendar date")
    func addTask() async throws {
        let id = try await repo.addTask(title: "开会", dueDate: d1116, dueTime: 15 * 60, tags: ["工作"], priority: .high)
        let t = try await f.task(id)
        #expect(t.title == "开会")
        #expect(t.listId == inboxListId)
        #expect(t.dueDate == d1116)
        #expect(try await f.db.writer.read { try String.fetchOne($0, sql: "SELECT due_date FROM tasks") } == "2026-11-16")
        #expect(t.dueTime == 900)
        #expect(t.tags == ["工作"])
        #expect(t.priority == .high)
        #expect(t.dirty)
        #expect(t.serverVersion == 0)
        // A UUID v7.
        #expect(Array(id)[14] == "7")
    }

    @Test("a time without a date is dropped")
    func timeWithoutDate() async throws {
        let id = try await repo.addTask(title: "x", dueTime: 60)
        #expect(try await f.task(id).dueTime == nil)
    }

    @Test("completing stamps completedAt and updatedAt")
    func completing() async throws {
        let id = try await repo.addTask(title: "x")
        clock.advance(minutes: 5)
        try await repo.setCompleted(id, true)
        var t = try await f.task(id)
        #expect(t.status == .done)
        #expect(t.completedAt == clock.ms)
        #expect(t.updatedAt == clock.ms)
        try await repo.setCompleted(id, false)
        t = try await f.task(id)
        #expect(t.status == .open)
        #expect(t.completedAt == nil)
    }

    @Test("trash, restore and purge")
    func trash() async throws {
        let id = try await repo.addTask(title: "x")
        try await repo.trashTask(id)
        #expect(try await f.tasks().first?.trashedAt != nil)
        try await repo.restoreTask(id)
        #expect(try await f.tasks().first?.trashedAt == nil)
        try await repo.trashTask(id)
        try await repo.emptyTrash()
        #expect(try await f.tasks().isEmpty)
        // The tombstone stays for sync.
        #expect(try await f.task(id).deletedAt != nil)

        // Purging one: its subtasks go with it.
        let other = try await repo.addTask(title: "y")
        let item = try await repo.addChecklistItem(other, "子")
        try await repo.purgeTask(other)
        #expect(try await f.task(other).deletedAt != nil)
        #expect(try await f.db.writer.read { try ChecklistItem.fetchOne($0, key: item) }?.deletedAt != nil)
    }

    @Test("deleting a list trashes its tasks")
    func deleteList() async throws {
        let listId = try await repo.addList("工作", emoji: "💼")
        let a = try await repo.addTask(title: "a", listId: listId)
        let b = try await repo.addTask(title: "b")
        try await repo.deleteList(listId)
        #expect(try await f.db.observeLists().first().isEmpty)
        let byId = Dictionary(uniqueKeysWithValues: try await f.tasks().map { ($0.id, $0) })
        #expect(byId[a]?.trashedAt != nil)
        #expect(byId[a]?.listId == inboxListId)
        #expect(byId[b]?.trashedAt == nil)
    }

    @Test("checklist items")
    func checklist() async throws {
        let id = try await repo.addTask(title: "x")
        let c1 = try await repo.addChecklistItem(id, "鸡蛋")
        clock.advance(seconds: 1)
        try await repo.addChecklistItem(id, "牛奶")
        try await repo.updateChecklistItem(c1, done: true)
        var items = try await f.checklist(id)
        #expect(items.map(\.title) == ["鸡蛋", "牛奶"])
        #expect(items.map(\.done) == [true, false])
        try await repo.deleteChecklistItem(c1)
        items = try await f.checklist(id)
        #expect(items.map(\.title) == ["牛奶"])
    }

    @Test("seedIfEmpty runs once")
    func seed() async throws {
        try await repo.seedIfEmpty()
        let n = try await f.tasks().count
        #expect(n > 0)
        try await repo.seedIfEmpty()
        #expect(try await f.tasks().count == n)
        #expect(openCount(.smart(.today), try await f.tasks(), LocalDateTime(clock.now)) == 1)
        #expect(try await f.db.getValue(Keys.seedIds)
            == #"["seed-welcome","seed-welcome-1","seed-welcome-2","seed-welcome-3","seed-today"]"#)

        // A signed-in device gets nothing.
        let g = try RepoFixture()
        let signedIn = TaskRepo(g.db, tokens: KeyValueTokenStore(g.db))
        try KeyValueTokenStore(g.db).setToken("t")
        try await signedIn.seedIfEmpty()
        #expect(try await g.tasks().isEmpty)
    }

    @Test("moving a task on the calendar starts reminders over between timed and all-day")
    func moveTo() async throws {
        let id = try await repo.addTask(title: "开会", dueDate: d1116, dueTime: 9 * 60, reminders: [0, -30], repeatRule: "FREQ=WEEKLY")
        // Another time keeps them: they count from the time.
        try await repo.moveTo(id, Day(2026, 11, 17), 14 * 60)
        var t = try await f.task(id)
        #expect(t.dueDate == Day(2026, 11, 17) && t.dueTime == 840 && t.reminders == [0, -30])
        #expect(t.repeatRule == "FREQ=WEEKLY")

        // All day: 准时 would mean midnight, so they go.
        try await repo.moveTo(id, Day(2026, 11, 18), nil)
        t = try await f.task(id)
        #expect(t.dueDate == Day(2026, 11, 18) && t.dueTime == nil && t.reminders == [])

        // Back to a time: 准时.
        try await repo.moveTo(id, Day(2026, 11, 18), 10 * 60)
        t = try await f.task(id)
        #expect(t.dueTime == 600 && t.reminders == [0])

        // Dropping it where it already is changes nothing.
        let before = t.updatedAt
        clock.advance(minutes: 1)
        try await repo.moveTo(id, Day(2026, 11, 18), 10 * 60)
        #expect(try await f.task(id).updatedAt == before)

        // Several at once.
        let other = try await repo.addTask(title: "别的")
        try await repo.moveAll([TaskMove(id: id, date: Day(2026, 11, 19), time: 600), TaskMove(id: other, date: Day(2026, 11, 19), time: nil)])
        #expect(try await f.task(id).dueDate == Day(2026, 11, 19))
        #expect(try await f.task(other).dueDate == Day(2026, 11, 19))
    }
}

@Suite struct RepeatingTaskTests {
    let f: RepoFixture
    var repo: TaskRepo { f.repo }
    var clock: TestClock { f.clock }
    init() throws { f = try RepoFixture() }

    func daily(rule: String = "FREQ=DAILY", from: RepeatFrom = .dueDate) async throws -> String {
        try await repo.addTask(title: "吃药", dueDate: d1115, dueTime: 8 * 60, reminders: [0], repeatRule: rule, repeatFrom: from)
    }

    @Test("completing moves the task on and leaves a finished copy")
    func moveOn() async throws {
        let id = try await daily()
        let item = try await repo.addChecklistItem(id, "饭后")
        try await repo.updateChecklistItem(item, done: true)
        clock.advance(minutes: 1)

        let done = try #require(try await repo.setCompleted(id, true))
        #expect(done.next == d1116)

        let t = try await f.task(id)
        #expect(t.status == .open)
        #expect(t.dueDate == d1116)
        #expect(t.dueTime == 8 * 60)
        #expect(t.reminders == [0])
        #expect(t.repeatRule == "FREQ=DAILY")
        // Subtasks start over.
        #expect(try await f.checklist(id).map(\.done) == [false])

        let copy = try await f.task(done.copyId)
        #expect(copy.title == "吃药")
        #expect(copy.status == .done)
        #expect(copy.completedAt == clock.ms)
        #expect(copy.dueDate == d1115)
        #expect(copy.repeatRule == nil)
        #expect(copy.reminders.isEmpty)
        #expect(copy.dirty)
        let copied = try await f.checklist(done.copyId)
        #expect(copied.map(\.title) == ["饭后"])
        #expect(copied.map(\.done) == [true])
    }

    @Test("the finished copy has the same id on every device")
    func sameId() async throws {
        let id = try await daily()
        let a = try #require(try await repo.setCompleted(id, true))
        // Same task, same occurrence: same id, wherever it is computed.
        let g = try RepoFixture(clock: clock)
        try await g.repo.addTask(id: id, title: "吃药", dueDate: d1115, repeatRule: "FREQ=DAILY")
        #expect(try await g.repo.setCompleted(id, true)?.copyId == a.copyId)
        // And the same as the Dart version's: UUID v5 of "<id>/<date>".
        #expect(a.copyId == uuidV5(namespace: Ids.occurrenceNamespace, name: "\(id)/2026-11-15"))
    }

    @Test("undo puts everything back")
    func undo() async throws {
        let id = try await daily()
        let item = try await repo.addChecklistItem(id, "饭后")
        try await repo.updateChecklistItem(item, done: true)
        let done = try #require(try await repo.setCompleted(id, true))
        try await repo.undoRepeatCompletion(done)

        let t = try await f.task(id)
        #expect(t.dueDate == d1115)
        #expect(t.status == .open)
        #expect(try await f.checklist(id).map(\.done) == [true])
        #expect(try await f.tasks().map(\.id) == [id])
        #expect(try await f.task(done.copyId).deletedAt != nil)

        // Completing again brings the copy back.
        let again = try #require(try await repo.setCompleted(id, true))
        #expect(again.copyId == done.copyId)
        #expect(try await f.task(done.copyId).deletedAt == nil)
    }

    @Test("the last occurrence closes the task")
    func last() async throws {
        let id = try await daily(rule: "FREQ=DAILY;COUNT=2")
        #expect(try await repo.setCompleted(id, true) != nil)
        #expect(try await f.task(id).repeatRule == "FREQ=DAILY;COUNT=1")
        #expect(try await repo.setCompleted(id, true) == nil)
        let t = try await f.task(id)
        #expect(t.status == .done)
        #expect(t.dueDate == d1116)
    }

    @Test("counting from completion")
    func fromCompletion() async throws {
        clock.set(LocalDateTime(2026, 11, 20, 9).date())
        let id = try await daily(rule: "FREQ=DAILY;INTERVAL=3", from: .completion)
        try await repo.setCompleted(id, true)
        #expect(try await f.task(id).dueDate == Day(2026, 11, 23))
    }

    @Test("skipping moves on without a copy")
    func skip() async throws {
        let id = try await daily(rule: "FREQ=WEEKLY;BYDAY=MO,FR")
        #expect(try await repo.skipOccurrence(id) == d1116)
        #expect(try await f.tasks().count == 1)
        #expect(try await f.task(id).status == .open)

        // Skipping a task that doesn't repeat gives it up.
        let once = try await repo.addTask(title: "一次", dueDate: d1115)
        #expect(try await repo.skipOccurrence(once) == nil)
        #expect(try await f.task(once).status == .wontDo)
    }

    @Test("clearing the date clears reminders and repeat")
    func clearDate() async throws {
        let id = try await daily()
        try await repo.setDue(id, Day(2026, 11, 20), 9 * 60)
        var t = try await f.task(id)
        #expect(t.reminders == [0])
        #expect(t.repeatRule == "FREQ=DAILY")
        try await repo.setDue(id, nil, nil)
        t = try await f.task(id)
        #expect(t.reminders.isEmpty)
        #expect(t.repeatRule == nil)
        // And completing it now is a plain completion.
        #expect(try await repo.setCompleted(id, true) == nil)
    }

    @Test("a task without a date takes no reminders or repeat")
    func undated() async throws {
        let id = try await repo.addTask(title: "x", reminders: [0], repeatRule: "FREQ=DAILY")
        let t = try await f.task(id)
        #expect(t.reminders.isEmpty)
        #expect(t.repeatRule == nil)
    }
}

@Suite struct SpanTests {
    let f: RepoFixture
    var repo: TaskRepo { f.repo }
    init() throws { f = try RepoFixture() }

    @Test("kept sensible when stored")
    func stored() async throws {
        let a = try await repo.addTask(title: "会", dueDate: d1116, dueTime: 600, duration: 90)
        let b = try await repo.addTask(title: "一天", dueDate: d1116, duration: 1440)
        let c = try await repo.addTask(title: "没日期", duration: 90)
        #expect(try await f.task(a).duration == 90)
        #expect(try await f.task(b).duration == nil)
        #expect(try await f.task(c).duration == nil)

        try await repo.setSchedule(a, date: Day(2026, 11, 17), duration: 2000)
        #expect(try await f.task(a).duration == 2880, "all day: whole days")
        try await repo.setDuration(a, 1440)
        #expect(try await f.task(a).duration == nil)
    }

    @Test("dragging moves the span; losing the time keeps its days")
    func dragging() async throws {
        let id = try await repo.addTask(title: "夜班", dueDate: d1116, dueTime: 22 * 60, duration: 180, reminders: [0])
        try await repo.moveTo(id, Day(2026, 11, 18), 21 * 60)
        var t = try await f.task(id)
        #expect(t.dueDate == Day(2026, 11, 18) && t.dueTime == 1260 && t.duration == 180 && t.reminders == [0])

        // 21:00 for three hours stays on one day.
        try await repo.moveTo(id, Day(2026, 11, 18), nil)
        t = try await f.task(id)
        #expect(t.dueTime == nil && t.duration == nil && t.reminders == [])

        try await repo.setSchedule(id, date: Day(2026, 11, 18), duration: 3 * 1440)
        try await repo.moveTo(id, Day(2026, 11, 20), 600)
        t = try await f.task(id)
        #expect(t.dueDate == Day(2026, 11, 20) && t.dueTime == 600 && t.duration == nil)
    }

    @Test("clearing the date clears the span; moving the day keeps it")
    func clearing() async throws {
        let id = try await repo.addTask(title: "会", dueDate: d1116, dueTime: 600, duration: 90)
        try await repo.setDue(id, Day(2026, 11, 17), 600)
        #expect(try await f.task(id).duration == 90)
        try await repo.setDue(id, nil, nil)
        #expect(try await f.task(id).duration == nil)
    }

    @Test("a repeating span keeps its length on the next date")
    func repeating() async throws {
        let id = try await repo.addTask(title: "周会", dueDate: d1116, dueTime: 600, duration: 60, repeatRule: "FREQ=WEEKLY")
        try await repo.setCompleted(id, true)
        let t = try await f.task(id)
        #expect(t.dueDate == Day(2026, 11, 23) && t.dueTime == 600 && t.duration == 60)
    }
}

@Suite struct DefaultsTests {
    @Test("the person's defaults go with a new date or a change of kind")
    func defaults() async throws {
        let defaults = Defaults(TaskDefaults(timedReminders: [-15], allDayReminders: [540]))
        let f = try RepoFixture(defaults: { defaults.current })
        let repo = f.repo
        let id = try await repo.addTask(title: "交报告")

        // First date from the menu: all day, so 当天 09:00.
        try await repo.setDue(id, d1116, nil)
        #expect(try await f.task(id).reminders == [540])
        // Moving it again keeps what it has.
        try await repo.setCompleted(id, false)
        try await repo.updateTask(id) { $0.reminders = [-900] }
        try await repo.setDue(id, Day(2026, 11, 17), nil)
        #expect(try await f.task(id).reminders == [-900])

        // Dragged onto an hour, then back to all day.
        try await repo.moveTo(id, Day(2026, 11, 17), 600)
        #expect(try await f.task(id).reminders == [-15])
        defaults.set(TaskDefaults(allDayReminders: []))
        try await repo.moveTo(id, Day(2026, 11, 17), nil)
        #expect(try await f.task(id).reminders.isEmpty)
    }
}

// MARK: - From sections_test.dart

private func shape(_ sections: [TaskSection]) -> [String] {
    sections.map { "\($0.title ?? "null"): \($0.tasks.map(\.title).joined(separator: ", "))" }
}

private func sec(_ title: String?, _ tasks: [String]) -> String {
    "\(title ?? "null"): \(tasks.joined(separator: ", "))"
}

@Suite struct SectionRepoTests {
    let f: RepoFixture
    var repo: TaskRepo { f.repo }
    let now = LocalDateTime(2026, 11, 15, 10)
    init() throws { f = try RepoFixture() }

    /// Adds tasks one second apart, so the later ones come first.
    func add(_ titles: [String], listId: String = "work", sectionId: String? = nil) async throws -> [String] {
        var ids: [String] = []
        for t in titles {
            f.clock.advance(seconds: 1)
            ids.append(try await repo.addTask(title: t, listId: listId, sectionId: sectionId))
        }
        return ids
    }

    func work() async throws -> [String: [ListSection]] {
        ["work": try await f.sections().filter { $0.listId == "work" }]
    }

    func build(_ byList: [String: [ListSection]] = [:]) async throws -> [TaskSection] {
        buildSections(view: .list("work"), tasks: try await f.tasks(), lists: [:], now: now, sectionsByList: byList)
    }

    @Test("sections go in order; a list without them has no headers")
    func inOrder() async throws {
        _ = try await add(["甲", "乙"])
        var s = try await build()
        #expect(shape(s) == [sec(nil, ["乙", "甲"])]) // newest first
        guard case .section? = s.first?.target else { Issue.record("not a section target"); return }

        let doing = try await repo.addSection("work", "进行中")
        let todo = try await repo.addSection("work", "待办")
        try await repo.addSection("home", "别的清单的")
        // Each list numbers its own: new ones go last.
        #expect(try await f.sections().filter { $0.listId == "work" }.map(\.name) == ["进行中", "待办"])
        #expect(try await f.sections().filter { $0.listId == "work" }.map(\.sortOrder) == [0, 1024])

        let byList = try await work()
        s = try await build(byList)
        // Unsectioned tasks first; empty sections still show, to drop into.
        #expect(shape(s) == [sec("未分组", ["乙", "甲"]), sec("进行中", []), sec("待办", [])])
        #expect(s[1].listSection?.id == doing)

        _ = try await add(["丙"], sectionId: todo)
        let all = try await f.tasks()
        let jia = all.first { $0.title == "甲" }!
        let yi = all.first { $0.title == "乙" }!
        // Drag 甲 above 乙 within 未分组, then 乙 into 进行中.
        try await repo.placeTask(jia.id, nil, planMove([yi.id, jia.id], jia.id, 0) { id in all.first { $0.id == id }!.sortOrder })
        f.clock.advance(seconds: 1)
        try await repo.placeTask(yi.id, doing, [yi.id: 0])
        s = try await build(byList)
        #expect(shape(s) == [sec("未分组", ["甲"]), sec("进行中", ["乙"]), sec("待办", ["丙"])])
        #expect(try await f.task(yi.id).dirty)

        // Once everything is sorted, 未分组 goes away.
        try await repo.placeTask(jia.id, todo, [jia.id: 99_999_999_999_999])
        s = try await build(byList)
        #expect(shape(s) == [sec("进行中", ["乙"]), sec("待办", ["丙", "甲"])])
    }

    @Test("deleting a section keeps its tasks; moving a task to another list leaves its section")
    func deleteSection() async throws {
        let doing = try await repo.addSection("work", "进行中")
        let ids = try await add(["甲", "乙"], sectionId: doing)
        let (a, b) = (ids[0], ids[1])
        f.clock.advance(seconds: 1)
        try await repo.deleteSection(doing)
        #expect(try await f.sections().isEmpty)
        #expect(try await f.task(a).sectionId == nil)
        #expect(try await f.task(a).trashedAt == nil)

        let review = try await repo.addSection("work", "评审")
        try await repo.placeTask(b, review, [b: 1])
        try await repo.moveToList(b, "home")
        #expect(try await f.task(b).listId == "home")
        #expect(try await f.task(b).sectionId == nil)
    }

    @Test("deleting a list deletes its sections")
    func deleteList() async throws {
        let listId = try await repo.addList("工作")
        let s = try await repo.addSection(listId, "进行中")
        let t = try await add(["甲"], listId: listId, sectionId: s)[0]
        try await repo.deleteList(listId)
        #expect(try await f.sections().isEmpty)
        let row = try #require(try await f.db.writer.read { try ListSection.fetchOne($0, key: s) })
        #expect(row.deletedAt != nil)
        #expect(row.dirty)
        #expect(try await f.task(t).trashedAt != nil)
        #expect(try await f.task(t).sectionId == nil)
    }

    @Test("renaming and moving a section")
    func updateSection() async throws {
        let s = try await repo.addSection("work", "进行中")
        f.clock.advance(minutes: 1)
        try await repo.updateSection(s, name: "在做", sortOrder: 5)
        let row = try #require(try await f.sections().first)
        #expect(row.name == "在做" && row.sortOrder == 5 && row.dirty && row.updatedAt == f.clock.ms)
    }
}

// MARK: - From pin_sort_test.dart

@Suite struct PinRepoTests {
    @Test("pinning is stored and synced; a finished copy of a repeating task is not pinned")
    func pinning() async throws {
        let f = try RepoFixture()
        let repo = f.repo
        let id = try await repo.addTask(title: "每天跑步", dueDate: d1115, repeatRule: "FREQ=DAILY")
        try await repo.setPinned(id, true)
        var t = try await f.task(id)
        #expect(t.pinnedAt == f.clock.ms)

        let wire = try #require(WireRecord(json: try JSONValue.decode(t.wire.json.encoded())))
        #expect(TodoTask(wire: wire).pinnedAt == t.pinnedAt)

        f.clock.advance(minutes: 1)
        try await repo.setCompleted(id, true)
        let all = try await f.tasks()
        #expect(all.first { $0.id != id }?.pinnedAt == nil) // the copy
        #expect(all.first { $0.id == id }?.pinnedAt != nil) // still pinned

        try await repo.setPinned(id, false)
        t = try await f.task(id)
        #expect(t.pinnedAt == nil)
    }
}

// MARK: - From grouping_test.dart

@Suite struct DropIntoTests {
    @Test("dropInto: each kind of group, in one go, with the new order")
    func dropInto() async throws {
        let f = try RepoFixture()
        let repo = f.repo
        let w = try await repo.addList("工作")
        let a = try await repo.addTask(title: "甲", dueDate: Day(2026, 11, 14), dueTime: 9 * 60, tags: ["x", "y"])
        let b = try await repo.addTask(title: "乙")

        try await repo.dropInto([a, b], .date(Day(2026, 11, 20)), [a: 5, b: 6])
        #expect(try await f.task(a).dueDate == Day(2026, 11, 20))
        #expect(try await f.task(a).dueTime == 9 * 60)
        #expect(try await f.task(b).dueDate == Day(2026, 11, 20))
        let orders = [try await f.task(a).sortOrder, try await f.task(b).sortOrder]
        #expect(orders == [5, 6])

        try await repo.dropInto([a], .date(nil), [:])
        #expect(try await f.task(a).dueDate == nil)
        #expect(try await f.task(a).dueTime == nil)

        try await repo.dropInto([a], .priority(.medium), [:])
        #expect(try await f.task(a).priority == .medium)

        try await repo.dropInto([a], .tag("z"), [:])
        #expect(try await f.task(a).tags == ["z", "y"])

        let section = try await repo.addSection(w, "进行中")
        try await repo.dropInto([a], .list(w), [:])
        #expect(try await f.task(a).listId == w)
        try await repo.dropInto([a], .section(listId: w, sectionId: section), [:])
        #expect(try await f.task(a).sectionId == section)
        // Into another list: out of the section.
        try await repo.dropInto([a], .list(inboxListId), [:])
        #expect(try await f.task(a).listId == inboxListId)
        #expect(try await f.task(a).sectionId == nil)

        // Only the order: nothing else changes.
        let before = try await f.task(b)
        try await repo.dropInto([b], .order, [b: -1])
        var after = try await f.task(b)
        #expect(after.sortOrder == -1)
        after.sortOrder = before.sortOrder
        after.updatedAt = before.updatedAt
        #expect(after == before)
    }
}

// MARK: - From timeline_test.dart

@Suite struct TimelineRepoTests {
    @Test("dated tasks move by the same days, undated ones go on the day, all into the section")
    func placeOnTimeline() async throws {
        let f = try RepoFixture()
        let repo = f.repo
        let list = try await repo.addList("工作")
        let s = try await repo.addSection(list, "本周")
        let meeting = try await repo.addTask(title: "会", listId: list, dueDate: d1115, dueTime: 9 * 60)
        try await repo.setDuration(meeting, 90)
        let trip = try await repo.addTask(title: "出差", listId: list, dueDate: d1116)
        try await repo.setDuration(trip, 3 * minutesPerDay)
        let idea = try await repo.addTask(title: "想法", listId: list)

        try await repo.placeOnTimeline([meeting, trip, idea], days: 2, day: Day(2026, 11, 20), target: .section(listId: list, sectionId: s))
        let m = try await f.task(meeting), t = try await f.task(trip), i = try await f.task(idea)
        #expect(m.dueDate == Day(2026, 11, 17) && m.dueTime == 9 * 60 && m.duration == 90 && m.sectionId == s)
        #expect(t.dueDate == Day(2026, 11, 18) && t.dueTime == nil && t.duration == 3 * minutesPerDay && t.sectionId == s)
        #expect(i.dueDate == Day(2026, 11, 20) && i.dueTime == nil && i.duration == nil && i.sectionId == s)

        // Another list, a tag, a priority: what the lane stands for.
        try await repo.placeOnTimeline([idea], days: 1, day: Day(2026, 11, 1), target: .list(inboxListId))
        #expect(try await f.task(idea).listId == inboxListId)
        try await repo.placeOnTimeline([idea], days: 0, day: Day(2026, 11, 1), target: .tag("会"))
        #expect(try await f.task(idea).tags == ["会"])
        try await repo.placeOnTimeline([idea], days: 0, day: Day(2026, 11, 1), target: .priority(.high))
        #expect(try await f.task(idea).priority == .high)
        #expect(try await f.task(idea).dueDate == Day(2026, 11, 21)) // moved a day with the first

        // Back to 未分组 without moving.
        try await repo.placeOnTimeline([meeting], days: 0, day: Day(2026, 11, 1), target: .section(listId: list, sectionId: nil))
        let back = try await f.task(meeting)
        #expect(back.dueDate == Day(2026, 11, 17) && back.sectionId == nil)
    }

    @Test("the left edge sets where it starts, keeping its time and reminders")
    func setStart() async throws {
        let f = try RepoFixture()
        let repo = f.repo
        let id = try await repo.addTask(title: "会", dueDate: d1115, dueTime: 9 * 60, reminders: [-15])
        try await repo.setDuration(id, 120)
        let t = try await f.task(id)
        let to = restartedSchedule(t, Day(2026, 11, 13))
        try await repo.setStart(id, to.date, to.duration)
        let m = try await f.task(id)
        #expect(m.dueDate == Day(2026, 11, 13) && m.dueTime == 9 * 60 && m.duration == 2 * minutesPerDay + 120 && m.reminders == [-15])
    }
}

// MARK: - The rest of the writes

@Suite struct OtherWriteTests {
    @Test("lists, filters, tags, title, content, priority, list: stamped and dirty")
    func stamped() async throws {
        let f = try RepoFixture()
        let repo = f.repo
        let l = try await repo.addList("工作", emoji: "💼")
        let filter = try await repo.addFilter("重要", "{}")
        let t = try await repo.addTask(title: "x")
        try await f.db.writer.write { try $0.execute(sql: "UPDATE task_lists SET dirty = 0; UPDATE task_filters SET dirty = 0; UPDATE tasks SET dirty = 0") }
        f.clock.advance(minutes: 1)
        try await repo.updateList(l, name: "公司")
        try await repo.updateFilter(filter, rule: #"{"match":"any"}"#)
        try await repo.setTitle(t, "y")
        try await repo.setContent(t, "备注")
        try await repo.setTags(t, ["a"])
        try await repo.setPriority(t, .low)
        try await repo.moveToList(t, l)
        let list = try #require(try await f.db.observeLists().first().first)
        #expect(list.name == "公司" && list.emoji == "💼" && list.dirty && list.updatedAt == f.clock.ms)
        let fl = try #require(try await f.db.observeFilters().first().first)
        #expect(fl.name == "重要" && fl.rule == #"{"match":"any"}"# && fl.dirty)
        let task = try await f.task(t)
        #expect(task.title == "y" && task.content == "备注" && task.tags == ["a"] && task.priority == .low && task.listId == l)
        #expect(task.dirty && task.updatedAt == f.clock.ms)

        try await repo.deleteFilter(filter)
        #expect(try await f.db.observeFilters().first().isEmpty)
        #expect(try await f.db.observeDirtyCount().first() == 3)
    }

    @Test("several tasks into one section together")
    func placeTasks() async throws {
        let f = try RepoFixture()
        let repo = f.repo
        let s = try await repo.addSection("work", "进行中")
        let a = try await repo.addTask(title: "a", listId: "work")
        let b = try await repo.addTask(title: "b", listId: "work")
        let c = try await repo.addTask(title: "c", listId: "work")
        try await repo.placeTasks([a, b], s, [a: 1, c: 3])
        let (ta, tb, tc) = (try await f.task(a), try await f.task(b), try await f.task(c))
        #expect(ta.sectionId == s && ta.sortOrder == 1)
        #expect(tb.sectionId == s)
        #expect(tc.sectionId == nil && tc.sortOrder == 3)
    }
}
