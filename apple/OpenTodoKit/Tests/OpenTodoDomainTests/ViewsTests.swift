// Ported from `app/test/views_test.dart`. The helpers at the top (`testNow`,
// `makeTask`, `shape`, `sec`) are shared by the other view, filter, search and
// timeline tests, as the Dart ones are.

import Foundation
import Synchronization
import Testing
@testable import OpenTodoDomain

/// The time zone the tests' epoch milliseconds are in.
let testZone = TimeZone(identifier: "Asia/Shanghai")!
let testNow = LocalDateTime(2026, 11, 15, 10) // Sunday

func millis(_ t: LocalDateTime) -> Int { Int(t.date(in: testZone).timeIntervalSince1970 * 1000) }
let testNowMillis = millis(testNow)

private let seq = Atomic<Int>(0)

/// A task whose id is its title; each one made is newer than the last
/// (later `createdAt`, smaller `sortOrder`), so manual order is newest first.
func makeTask(
    _ title: String,
    listId: String = inboxListId,
    due: String? = nil,
    time: Int? = nil,
    duration: Int? = nil,
    priority: Priority = .none,
    status: TaskStatus = .open,
    completedAt: Int? = nil,
    trashedAt: Int? = nil,
    tags: [String] = [],
    reminders: [Int] = [],
    content: String = "",
    sectionId: String? = nil,
    pinnedAt: Int? = nil
) -> TodoTask {
    let created = testNowMillis + seq.wrappingAdd(1, ordering: .relaxed).oldValue
    return TodoTask(
        id: title, listId: listId, sectionId: sectionId, title: title, content: content, priority: priority,
        dueDate: due.map { Day($0)! }, dueTime: time, duration: duration, tags: tags, status: status,
        completedAt: completedAt, reminders: reminders, pinnedAt: pinnedAt, trashedAt: trashedAt,
        sortOrder: -Double(created), createdAt: created, updatedAt: created
    )
}

/// `title: a, b` per section, so failures print readably.
func shape(_ sections: [TaskSection]) -> [String] {
    sections.map { "\($0.title ?? "null"): \($0.tasks.map(\.title).joined(separator: ", "))" }
}

func sec(_ title: String?, _ tasks: [String]) -> String {
    "\(title ?? "null"): \(tasks.joined(separator: ", "))"
}

func day(_ s: String) -> Day { Day(s)! }

@Suite("views")
struct ViewsTests {
    let tasks = [
        makeTask("过期", due: "2026-11-10"),
        makeTask("晨会", due: "2026-11-15", time: 9 * 60),
        makeTask("全天", due: "2026-11-15"),
        makeTask("写周报", due: "2026-11-15", time: 15 * 60, priority: .high),
        makeTask("买菜", due: "2026-11-16"),
        makeTask("读书", due: "2026-11-18", tags: ["自我提升"]),
        makeTask("远期", due: "2026-12-01"),
        makeTask("无日期"),
        makeTask("工作任务", listId: "work", tags: ["自我提升"]),
        makeTask("做完了", due: "2026-11-15", status: .done, completedAt: testNowMillis),
        makeTask("早就做完", due: "2026-11-01", status: .done, completedAt: millis(LocalDateTime(2026, 11, 1))),
        makeTask("删掉的", due: "2026-11-15", trashedAt: testNowMillis),
    ]

    func sections(_ v: ViewRef) -> [TaskSection] {
        buildSections(view: v, tasks: tasks, lists: [:], now: testNow, timeZone: testZone)
    }

    @Test("today: overdue first, all-day before timed, finished today at the end")
    func today() {
        #expect(shape(sections(.smart(.today))) == [
            sec("已过期", ["过期"]),
            sec("今天, 周日", ["全天", "晨会", "写周报"]),
            sec("已完成", ["做完了"]),
        ])
    }

    @Test("tomorrow")
    func tomorrow() {
        #expect(shape(sections(.smart(.tomorrow))) == [sec("明天, 周一", ["买菜"])])
    }

    @Test("next 7 days groups by day")
    func next7() {
        // (The empty days are left out here; see PinSortTests.)
        #expect(shape(sections(.smart(.next7)).filter { !$0.tasks.isEmpty }) == [
            sec("已过期", ["过期"]),
            sec("今天, 周日", ["全天", "晨会", "写周报"]),
            sec("明天, 周一", ["买菜"]),
            sec("11月18日, 周三", ["读书"]),
            sec("已完成", ["做完了"]),
        ])
    }

    @Test("inbox: newest first, finished collapsed at the end")
    func inbox() {
        let s = sections(.smart(.inbox))
        #expect(s.first?.title == nil)
        #expect(s.first?.tasks.first?.title == "无日期")
        let inboxTitles = s.first?.tasks.map(\.title) ?? []
        #expect(!inboxTitles.contains("工作任务"))
        #expect(s.last?.title == "已完成")
    }

    @Test("a list")
    func aList() {
        #expect(shape(sections(.list("work"))) == [sec(nil, ["工作任务"])])
    }

    @Test("a tag groups by list")
    func aTag() {
        #expect(shape(sections(.tag("自我提升"))) == [
            sec("收集箱", ["读书"]),
            sec("收集箱", ["工作任务"]),
        ])
    }

    @Test("completed groups by the day it was finished")
    func completed() {
        #expect(shape(sections(.smart(.completed))) == [
            sec("今天, 周日", ["做完了"]),
            sec("11月1日, 周日", ["早就做完"]),
        ])
    }

    @Test("trash")
    func trash() {
        #expect(shape(sections(.smart(.trash))) == [sec(nil, ["删掉的"])])
    }

    @Test("counts are open tasks only")
    func counts() {
        #expect(openCount(.smart(.today), tasks, testNow) == 4)
        #expect(openCount(.smart(.next7), tasks, testNow) == 6)
        #expect(openCount(.smart(.inbox), tasks, testNow) == 8)
    }

    @Test("dateViewShows")
    func dateViewShowsTest() {
        let today = Day(2026, 11, 15)
        #expect(dateViewShows(.smart(.today), today, today))
        #expect(!dateViewShows(.smart(.today), Day(2026, 11, 16), today))
        #expect(dateViewShows(.smart(.next7), Day(2026, 11, 21), today))
        #expect(!dateViewShows(.smart(.next7), Day(2026, 11, 22), today))
        #expect(dateViewShows(.list("work"), Day(2030, 1, 1), today))
    }

    @Test("quick-add defaults follow the view")
    func quickAdd() {
        let today = Day(2026, 11, 15)
        #expect(quickAddDefaults(.smart(.tomorrow), today).date == Day(2026, 11, 16))
        #expect(quickAddDefaults(.list("work"), today).listId == "work")
        #expect(quickAddDefaults(.tag("x"), today).tags == ["x"])
    }

    @Test("overdue: an earlier day, or today once the time comes")
    func overdue() {
        // 16:56:30; seconds don't count.
        let at = LocalDateTime(Date(timeIntervalSince1970: Double(millis(LocalDateTime(2026, 11, 15, 16, 56))) / 1000 + 30), in: testZone)
        func overdue(_ t: TodoTask) -> Bool { isOverdue(t, at) }
        #expect(overdue(makeTask("昨天", due: "2026-11-14")))
        #expect(overdue(makeTask("昨天晚上", due: "2026-11-14", time: 23 * 60)))
        #expect(!overdue(makeTask("今天全天", due: "2026-11-15")))
        #expect(overdue(makeTask("刚过", due: "2026-11-15", time: 16 * 60 + 55)))
        // The minute it is due, as its 准时 reminder goes off.
        #expect(overdue(makeTask("正到点", due: "2026-11-15", time: 16 * 60 + 56)))
        #expect(!overdue(makeTask("还没到", due: "2026-11-15", time: 16 * 60 + 57)))
        #expect(!overdue(makeTask("明天", due: "2026-11-16")))
        #expect(!overdue(makeTask("没日期")))
        #expect(!overdue(makeTask("做完了", due: "2026-11-14", status: .done)))
        #expect(!overdue(makeTask("删了", due: "2026-11-14", trashedAt: 1)))
    }

    // MARK: spans (Sunday 10:00)

    @Test("spans: a span is due when it ends")
    func spanDue() {
        #expect(!isOverdue(makeTask("会", due: "2026-11-15", time: 9 * 60, duration: 120), testNow))
        #expect(isOverdue(makeTask("会", due: "2026-11-15", time: 8 * 60, duration: 120), testNow))
        // All day, Saturday to Monday: still on.
        #expect(!isOverdue(makeTask("出差", due: "2026-11-14", duration: 3 * 1440), testNow))
        #expect(isOverdue(makeTask("出差", due: "2026-11-13", duration: 2 * 1440), testNow))
    }

    @Test("spans: a span shows on each day it covers, once per view")
    func spanDays() {
        let trip = makeTask("出差", due: "2026-11-14", duration: 3 * 1440) // Sat-Mon
        let later = makeTask("培训", due: "2026-11-17", duration: 2 * 1440) // Tue-Wed
        let done = makeTask("旧的", due: "2026-11-12", duration: 2 * 1440) // Thu-Fri

        func titles(_ kind: SmartKind) -> [String] {
            buildSections(view: .smart(kind), tasks: [trip, later, done], lists: [:], now: testNow)
                .filter { !$0.tasks.isEmpty }
                .map { "\($0.title ?? "null"): \($0.tasks.map(\.title).joined(separator: ","))" }
        }

        #expect(titles(.today) == ["已过期: 旧的", "今天, 周日: 出差"])
        #expect(titles(.tomorrow) == ["明天, 周一: 出差"])
        #expect(titles(.next7) == ["已过期: 旧的", "今天, 周日: 出差", "11月17日, 周二: 培训"])
        #expect(openCount(.smart(.tomorrow), [trip, later], testNow) == 1)
    }

    // Not in the Dart tests: the fast local day 已完成 groups by.
    @Test("localDay is the calendar's day, in any zone, across DST")
    func localDays() {
        var x: UInt64 = 7
        for zone in ["Asia/Shanghai", "America/New_York", "Europe/London", "Australia/Lord_Howe", "Pacific/Chatham", "UTC"] {
            let tz = TimeZone(identifier: zone)!
            for _ in 0..<2000 {
                x = x &* 6364136223846793005 &+ 1442695040888963407
                // 1950 … 2060, to the millisecond, negative ones too.
                let ms = Int(x >> 22) % 3_470_000_000_000 - 630_000_000_000
                #expect(localDay(ms, tz) == Day(Date(timeIntervalSince1970: Double(ms) / 1000), in: tz), "\(zone) \(ms)")
            }
        }
    }

    // Not in the Dart tests: every count in one pass is each view's count.
    @Test("openCounts is openCount for every view")
    func countsAtOnce() {
        var all = tasks
        all.append(makeTask("两个标签", due: "2026-11-16", tags: ["自我提升", "家", "家"]))
        all.append(makeTask("跨天", due: "2026-11-14", duration: 3 * 1440))
        let rules = ["f": FilterRule(conditions: [FilterCondition(.date, ["today", "overdue"])]),
                     "g": FilterRule(matchAll: false, conditions: [FilterCondition(.tag, ["家"]), FilterCondition(.list, ["work"])])]
        let c = openCounts(all, testNow, rules)
        var views: [ViewRef] = SmartKind.allCases.map(ViewRef.smart)
        views += ["work", "inbox", "gone"].map(ViewRef.list)
        views += ["自我提升", "家", "无"].map(ViewRef.tag)
        views += ["f", "g", "missing"].map(ViewRef.filter)
        for v in views {
            #expect(c[v] == openCount(v, all, testNow, rules), "\(v)")
        }
    }

    // Not in the Dart tests: the rest of views.dart's small helpers.

    @Test("view titles, refs and where a task opens")
    func titlesAndRefs() {
        let lists = ["w": TaskList(id: "w", name: "工作")]
        #expect(viewTitle(.smart(.next7), lists) == "最近7天")
        #expect(viewTitle(.list("w"), lists) == "工作")
        #expect(viewTitle(.list("gone"), lists) == "收集箱")
        #expect(viewTitle(.tag("家"), lists) == "#家")
        #expect(viewTitle(.filter("f"), lists, ["f": TaskFilter(id: "f", name: "本周")]) == "本周")
        #expect(ViewRef.smart(.today).description == "smart:today")
        #expect(ViewRef.list("w").description == "list:w")
        #expect(!canQuickAdd(.smart(.trash)) && canQuickAdd(.tag("x")))
        #expect(timelineGroupingsFor(.smart(.today)) == [.list, .tag, .priority, .none])
        #expect(timelineGroupingsFor(.list("w")) == [.sections])

        #expect(viewForTask(tasks[7], .smart(.inbox), testNow) == .smart(.inbox))
        #expect(viewForTask(tasks[0], .smart(.tomorrow), testNow) == .smart(.today))
        #expect(viewForTask(tasks[8], .smart(.today), testNow) == .list("work"))
        #expect(viewForTask(tasks[6], .tag("x"), testNow) == .smart(.inbox))
        #expect(viewForTask(tasks[9], .smart(.inbox), testNow) == .smart(.inbox))
        #expect(viewForTask(tasks[9], .list("work"), testNow) == .smart(.completed))
        #expect(viewForTask(tasks[11], .smart(.today), testNow) == .smart(.trash))
    }
}
