import Foundation
import Testing
@testable import OpenTodoSystem

/// Thursday 26 November 2026, 14:20.
private let now = LocalDateTime(2026, 11, 26, 14, 20)
private let today = now.day

private func task(_ id: String, _ title: String = "", due: Day? = nil, time: Int? = nil, duration: Int? = nil,
                  priority: Priority = .none, list: String = inboxListId, done: Bool = false,
                  trashed: Bool = false, rule: String? = nil) -> TodoTask {
    TodoTask(id: id, listId: list, title: title.isEmpty ? id : title, priority: priority, dueDate: due,
             dueTime: time, duration: duration, status: done ? .done : .open, repeatRule: rule,
             trashedAt: trashed ? 1 : nil)
}

// MARK: - Links

@Suite struct AppLinks {
    @Test(arguments: [AppLink.task("01J9-abc"), .list("work"), .today, .quickAdd, .habits, .countdowns, .focus])
    func roundTrip(_ link: AppLink) {
        #expect(AppLink(link.url(scheme: "opentodo")) == link)
        #expect(AppLink(link.url(scheme: "opentodo-dev")) == link)
    }

    @Test func readsTheDocumentedForms() {
        #expect(AppLink(URL(string: "opentodo://task/t1")!) == .task("t1"))
        #expect(AppLink(URL(string: "OpenTodo://TASK/t1")!) == .task("t1"))
        #expect(AppLink(URL(string: "opentodo-dev://list/work")!) == .list("work"))
        #expect(AppLink(URL(string: "opentodo://quickadd")!) == .quickAdd)
        #expect(AppLink(URL(string: "opentodo://today/")!) == .today)
    }

    @Test func idsAreEscaped() {
        let link = AppLink.task("a b/c#d")
        let url = link.url(scheme: "opentodo")
        #expect(url.absoluteString == "opentodo://task/a%20b%2Fc%23d")
        #expect(AppLink(url) == link)
    }

    @Test(arguments: ["https://task/t1", "opentodo://task", "opentodo://task/", "opentodo://task/a/b",
                      "opentodo://nowhere", "opentodo://today/x", "opentodo:task/t1"])
    func rejects(_ text: String) {
        #expect(AppLink(URL(string: text)!) == nil)
    }

    @Test func schemeFromTheBundle() {
        #expect(AppLink.scheme(Bundle(for: BundleToken.self)) == "opentodo") // no OTURLScheme: the release one
    }
}

private final class BundleToken {}

// MARK: - The today widget

@Suite struct TodayWidgetContent {
    let lists = [TaskList(id: "work", name: "工作")]

    @Test func inTheTodayViewsOrderOnlyOpenOnes() {
        let tasks = [
            task("later", due: today, time: 18 * 60, list: "work"),
            task("allday", due: today),
            task("old", due: today - 2, priority: .high),
            task("morning", due: today, time: 9 * 60),
            task("done", due: today, done: true),
            task("trashed", due: today, trashed: true),
            task("tomorrow", due: today + 1),
            task("undated"),
        ]
        let w = todayWidget(tasks, lists: lists, now: now, limit: 10)
        // The 今天 view's order: earlier days, then today's all-day ones, then by time.
        #expect(w.tasks.map(\.id) == ["old", "allday", "morning", "later"])
        #expect(w.total == 4)
        #expect(w.overdue == 2) // 2 days ago, and 9:00 has passed
        #expect(Set(w.tasks.map(\.id)) == ["old", "morning", "allday", "later"])
        let byId = Dictionary(uniqueKeysWithValues: w.tasks.map { ($0.id, $0) })
        #expect(byId["old"]?.timeText == "11月24日")
        #expect(byId["old"]?.priority == .high)
        #expect(byId["morning"]?.timeText == "上午9:00")
        #expect(byId["morning"]?.overdue == true)
        #expect(byId["allday"]?.timeText == nil)
        #expect(byId["later"]?.listName == "工作")
        #expect(byId["allday"]?.listName == "收集箱")
    }

    @Test func limitAndMore() {
        let tasks = (0..<8).map { task("t\($0)", due: today, time: 15 * 60 + $0) }
        let w = todayWidget(tasks, lists: [], now: now, limit: 3)
        #expect(w.tasks.map(\.id) == ["t0", "t1", "t2"])
        #expect(w.total == 8)
        #expect(w.more == 5)
        #expect(todayWidget([], lists: [], now: now, limit: 3) == TodayWidget(today: today))
    }

    @Test func spansThatHaveStarted() {
        // Started yesterday evening, still going: today's, by its time.
        let s = task("span", due: today - 1, time: 22 * 60, duration: 24 * 60)
        let w = todayWidget([s], lists: [], now: now, limit: 5)
        #expect(w.tasks.map(\.id) == ["span"])
        #expect(w.tasks[0].overdue == false)
        #expect(w.tasks[0].timeText == "下午10:00-10:00")
        #expect(widgetTimeText(task("x", due: today, time: 600, duration: 90), now: now) == "上午10:00-11:30")
        #expect(widgetTimeText(task("y", due: today - 1, time: 600), now: now) == "昨天")
    }

    @Test func repeatsMarked() {
        let w = todayWidget([task("r", due: today, rule: "FREQ=DAILY")], lists: [], now: now, limit: 5)
        #expect(w.tasks[0].repeats)
    }
}

@Suite struct WidgetRefresh {
    @Test func atTheNextDueMomentsAndMidnight() {
        let tasks = [
            task("past", due: today, time: 9 * 60),            // already due
            task("soon", due: today, time: 15 * 60),
            task("span", due: today, time: 16 * 60, duration: 90), // due when it ends
            task("same", due: today, time: 15 * 60),            // the same moment once
            task("tomorrow", due: today + 1, time: 8 * 60),
            task("later", due: today + 3, time: 8 * 60),       // beyond the timeline
            task("done", due: today, time: 20 * 60, done: true),
            task("allday", due: today),
        ]
        #expect(widgetRefreshTimes(tasks, now: now) == [
            LocalDateTime(today, minute: 15 * 60),
            LocalDateTime(today, minute: 17 * 60 + 30),
            LocalDateTime(today + 1),
            LocalDateTime(today + 1, minute: 8 * 60),
        ])
        #expect(widgetRefreshTimes([], now: now) == [LocalDateTime(today + 1)])
        #expect(widgetRefreshTimes(tasks, now: now, limit: 2).count == 2)
    }
}

// MARK: - Habits, countdowns, focus

@Suite struct OtherWidgets {
    @Test func habitsOfToday() {
        let water = Habit(id: "water", name: "喝水", goalKind: .count, goal: 8, unit: "杯", startDate: today - 10)
        let read = Habit(id: "read", name: "读书", startDate: today - 10)
        let archived = Habit(id: "old", name: "旧的", startDate: today - 10, archivedAt: 1)
        let checkins = [
            HabitCheckin(habitId: "water", day: today, value: 3, status: .partial),
            HabitCheckin(habitId: "read", day: today, value: 1, status: .done),
            HabitCheckin(habitId: "read", day: today - 1, value: 1, status: .done),
        ]
        let w = habitsWidget([water, read, archived], checkins: checkins, today: today)
        #expect(Set(w.habits.map(\.id)) == ["water", "read"])
        let byId = Dictionary(uniqueKeysWithValues: w.habits.map { ($0.id, $0) })
        #expect(byId["read"]?.done == true)
        #expect(byId["read"]?.progress == 1)
        #expect(byId["read"]?.amountText == nil)
        #expect(byId["water"]?.done == false)
        #expect(byId["water"]?.amountText == "3/8杯")
        #expect(abs((byId["water"]?.progress ?? 0) - 0.375) < 0.001)
        #expect((w.done, w.due) == (1, 2))
    }

    @Test func countdownPickedOrFirst() {
        let trip = Countdown(id: "trip", title: "旅行", kind: .countdown, date: today + 10)
        let exam = Countdown(id: "exam", title: "考试", kind: .countdown, date: today + 3)
        let wed = Countdown(id: "wed", title: "结婚纪念日", kind: .anniversary, date: Day(2020, 5, 20))
        let first = widgetCountdown([trip, exam, wed], picked: nil, today: today)
        #expect(first?.id == "exam")
        #expect(first?.days == 3)
        #expect(first?.lead == "还有")
        #expect(first?.dateText == "2026年11月29日 周日")
        let picked = widgetCountdown([trip, exam, wed], picked: "wed", today: today)
        #expect(picked?.past == true)
        #expect(picked?.lead == "已经")
        #expect(picked?.days == Day(2020, 5, 20).days(to: today))
        #expect(widgetCountdown([trip], picked: "gone", today: today)?.id == "trip")
        #expect(widgetCountdown([], picked: nil, today: today) == nil)
    }

    @Test func focusText() {
        #expect(focusDurationText(seconds: 0) == "0分钟")
        #expect(focusDurationText(seconds: 25 * 60 + 59) == "25分钟")
        #expect(focusDurationText(seconds: 3600) == "1小时")
        #expect(focusDurationText(seconds: 85 * 60) == "1小时25分钟")
        #expect(focusDurationText(seconds: -5) == "0分钟")
    }
}

// MARK: - Sharing

@Suite struct Sharing {
    @Test func aPageWithItsTitle() {
        let d = shareDraft(SharedItem(url: URL(string: "https://example.com/post/1")!, pageTitle: "  一篇文章 "))
        #expect(d == ShareDraft(title: "一篇文章", content: "https://example.com/post/1"))
    }

    @Test func aLinkWithoutATitle() {
        let d = shareDraft(SharedItem(url: URL(string: "https://www.example.com/post/1")!))
        #expect(d == ShareDraft(title: "example.com/post/1", content: "https://www.example.com/post/1"))
        #expect(shareDraft(SharedItem(url: URL(string: "https://example.com/")!)).title == "example.com")
    }

    @Test func plainText() {
        #expect(shareDraft(SharedItem(text: "买牛奶")) == ShareDraft(title: "买牛奶"))
        #expect(shareDraft(SharedItem(text: "周会纪要\n\n1. 上线\n2. 招聘")) == ShareDraft(title: "周会纪要", content: "1. 上线\n2. 招聘"))
    }

    @Test func textWithALinkInIt() {
        // As apps share "title + link" in one string.
        let d = shareDraft(SharedItem(text: "这个值得一看 https://example.com/a?b=1"))
        #expect(d == ShareDraft(title: "这个值得一看", content: "https://example.com/a?b=1"))
        // Only a link: the address is the title.
        #expect(shareDraft(SharedItem(text: "https://example.com/x")) == ShareDraft(title: "example.com/x", content: "https://example.com/x"))
    }

    @Test func textAndTheSameLink() {
        let d = shareDraft(SharedItem(text: "读一下 https://example.com/a", url: URL(string: "https://example.com/a")!, pageTitle: "文章"))
        #expect(d == ShareDraft(title: "文章", content: "https://example.com/a\n\n读一下"))
    }

    @Test func aLongFirstLine() {
        let long = String(repeating: "字", count: 250)
        let d = shareDraft(SharedItem(text: long))
        #expect(d.title.count == shareTitleLimit)
        #expect(d.content.count == 50)
    }

    @Test func nothing() {
        #expect(shareDraft(SharedItem(text: "   ")) == ShareDraft(title: ""))
    }
}

// MARK: - Writing from outside

@Suite struct Writing {
    @Test func anExtensionDoesNotMakeTheDatabaseBeforeTheApp() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ot-writer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("opentodo.sqlite")
        #expect(throws: SharedWriterError.appNotOpenedYet) { try SharedWriter.open(at: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        _ = try AppDatabase.open(at: url) // the app's first launch
        let writer = try SharedWriter.open(at: url)
        _ = try await writer.add(title: "买牛奶")
    }

    @Test func completeAndAdd() async throws {
        let db = try AppDatabase.inMemory()
        let writer = SharedWriter(db)
        let id = try await writer.add(title: "买牛奶", content: "https://example.com", listId: "nowhere", date: today, time: 600)
        var t = try #require(try await writer.repo.getTask(id))
        #expect(t.listId == inboxListId) // an unknown list: the inbox
        #expect(t.content == "https://example.com")
        #expect((t.dueDate, t.dueTime, t.reminders) == (today, 600, [0])) // the default 准时
        try await writer.complete(id)
        t = try #require(try await writer.repo.getTask(id))
        #expect(t.status == .done)
        try await writer.complete("gone") // nothing happens
        let undated = try await writer.add(title: "读书")
        #expect(try await writer.repo.getTask(undated)?.reminders == [])
    }

    @Test func signalName() {
        #expect(ChangeSignal.name(appGroup: "group.com.liaoxingyi.opentodo") == "group.com.liaoxingyi.opentodo.changed")
        #expect(ChangeSignal.name(appGroup: nil) == "com.liaoxingyi.opentodo.changed")
    }
}

// MARK: - Hot key

@Suite struct HotKeys {
    @Test func theDefault() {
        let k = HotKey.quickAddDefault
        #expect(k.display == "⌃⇧A")
        #expect(k.carbonModifiers == 0x1000 | 0x200)
        #expect(k.isValid)
    }

    @Test func displayOrder() {
        let k = HotKey(keyCode: 49, modifiers: [.command, .shift, .option, .control], keyName: "Space")
        #expect(k.display == "⌃⌥⇧⌘Space")
        #expect(k.carbonModifiers == 0x1B00)
    }

    @Test func storage() {
        let k = HotKey(keyCode: 3, modifiers: [.command, .option], keyName: "F")
        #expect(HotKey(storage: k.storage) == k)
        #expect(HotKey(storage: "0:4:A") == nil) // shift alone
        #expect(HotKey(storage: "x:1:A") == nil)
        #expect(HotKey(storage: "0:1:") == nil)
        #expect(HotKey(storage: "12:1:a:b")?.keyName == "a:b")
    }

    @Test func keyNames() {
        #expect(HotKey.keyName(keyCode: 0, characters: "a") == "A")
        #expect(HotKey.keyName(keyCode: 49, characters: " ") == "Space")
        #expect(HotKey.keyName(keyCode: 122, characters: nil) == "F1")
        #expect(HotKey.keyName(keyCode: 126, characters: nil) == "↑")
        #expect(HotKey.keyName(keyCode: 200, characters: "") == "#200")
    }

    @Test func prefs() {
        let d = UserDefaults(suiteName: "hotkey-test-\(UUID())")!
        #expect(IntegrationPrefs.hotKey(d) == .quickAddDefault)
        d.set("3:8:F", forKey: IntegrationPrefs.hotKeyKey)
        #expect(IntegrationPrefs.hotKey(d)?.display == "⌘F")
        d.set(false, forKey: IntegrationPrefs.hotKeyEnabledKey)
        #expect(IntegrationPrefs.hotKey(d) == nil)
    }
}

// MARK: - Spotlight

@Test func spotlightIndexesOpenTasks() {
    let lists = [TaskList(id: "work", name: "工作")]
    var report = task("r", "写周报", due: today + 1, time: 900, list: "work")
    report.tags = ["工作"]
    report.content = "重点写上线的项目\n第二行"
    let entries = spotlightEntries([report, task("d", due: today, done: true), task("t", trashed: true), task("i", "买牛奶")],
                                   lists: lists, today: today)
    #expect(entries == [
        SpotlightEntry(id: "r", title: "写周报", details: "工作 · 明天, 下午3:00 · 重点写上线的项目", keywords: ["工作"]),
        SpotlightEntry(id: "i", title: "买牛奶", details: "收集箱", keywords: []),
    ])
}

// MARK: - 添加任务's date and time

@Test func intentDateAndTime() {
    let tz = TimeZone(identifier: "Asia/Shanghai")!
    let date = LocalDateTime(2026, 12, 3, 0, 0).date(in: tz)
    let time = LocalDateTime(2000, 1, 1, 15, 30).date(in: tz)
    let now = LocalDateTime(2026, 11, 26, 9, 0).date(in: tz)
    #expect(intentDue(date: nil, time: nil, now: now, in: tz) == (nil, nil))
    #expect(intentDue(date: date, time: nil, now: now, in: tz) == (Day(2026, 12, 3), nil))
    #expect(intentDue(date: date, time: time, now: now, in: tz) == (Day(2026, 12, 3), 930))
    #expect(intentDue(date: nil, time: time, now: now, in: tz) == (Day(2026, 11, 26), 930)) // today
}
