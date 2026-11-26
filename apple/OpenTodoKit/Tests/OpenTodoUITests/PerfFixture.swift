// A big, realistic account for the performance tests: 5000 tasks (3500
// finished) in 20 lists with sections, tags, dates, times, spans, repeats,
// reminders and 8000 subtasks, made the same way every run (a seeded
// generator), dated around a fixed now.

import Foundation
import GRDB
@testable import OpenTodoData
import OpenTodoDomain
@testable import OpenTodoUI

nonisolated let perfZone = TimeZone(identifier: "Asia/Shanghai")!
nonisolated let perfNow = LocalDateTime(2026, 11, 26, 9, 41) // Thursday
nonisolated let perfToday = perfNow.day
nonisolated let perfNowMs = Int(perfNow.date(in: perfZone).timeIntervalSince1970 * 1000)

/// The biggest list (a quarter of the tasks).
nonisolated let perfBigList = "l0"

nonisolated let perfData: TaskData = makePerfData()

/// SplitMix64: the same numbers every run.
nonisolated private struct Seeded {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ range: Range<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
    mutating func chance(_ p: Double) -> Bool { Double(next() % 10_000) < p * 10_000 }
    mutating func pick<T>(_ a: [T]) -> T { a[int(0..<a.count)] }
}

nonisolated func makePerfData(tasks taskCount: Int = 5000, finished: Int = 3500, subtasks: Int = 8000) -> TaskData {
    var r = Seeded(state: 42)
    let listNames = ["工作", "生活", "购物", "读书", "健身", "项目甲", "项目乙", "家务", "学习", "旅行",
                     "财务", "健康", "朋友", "孩子", "装修", "写作", "摄影", "音乐", "灵感", "杂事"]
    let lists = listNames.enumerated().map { i, name in
        TaskList(id: "l\(i)", name: name, sortOrder: Double(i), createdAt: i, updatedAt: i, dirty: false)
    }
    var sections: [ListSection] = []
    for l in lists {
        for (j, name) in ["进行中", "待安排", "以后"].enumerated() {
            sections.append(ListSection(id: "\(l.id)-s\(j)", listId: l.id, name: name, sortOrder: Double(j), dirty: false))
        }
    }
    let tags = ["工作", "家", "学习", "健身", "阅读", "采购", "会议", "出差", "紧急", "周报", "项目A", "项目B", "灵感", "财务", "健康"]
    let verbs = ["写", "整理", "准备", "回复", "检查", "安排", "阅读", "购买", "预约", "提交", "修改", "讨论"]
    let nouns = ["周报", "文档", "会议纪要", "邮件", "方案", "报销单", "合同", "设计稿", "代码评审", "资料", "预算", "演讲稿"]
    let repeats = ["FREQ=DAILY", "FREQ=WEEKLY;BYDAY=MO,WE", "FREQ=MONTHLY;BYMONTHDAY=15", "FREQ=YEARLY", "FREQ=DAILY;INTERVAL=3"]
    let day = 86_400_000

    var tasks: [TodoTask] = []
    tasks.reserveCapacity(taskCount)
    for i in 0..<taskCount {
        // A quarter in the first list, the rest spread.
        let list = r.chance(0.25) ? lists[0] : r.pick(lists)
        let done = i < finished
        var t = TodoTask(id: "t\(i)", listId: list.id, title: "\(r.pick(verbs))\(r.pick(nouns)) \(i)")
        t.createdAt = perfNowMs - r.int(0..<(800 * day))
        t.updatedAt = t.createdAt + r.int(0..<day)
        t.sortOrder = Double(r.int(0..<1_000_000))
        t.dirty = r.chance(0.02)
        if r.chance(0.6) { t.sectionId = "\(list.id)-s\(r.int(0..<3))" }
        if r.chance(0.5) { t.tags = (0..<r.int(1..<3)).map { _ in r.pick(tags) } }
        t.priority = Priority(rawValue: r.int(0..<4))!
        if r.chance(0.2) { t.content = "备注：\(r.pick(nouns))相关，记得和\(r.pick(listNames))一起看" }
        if done {
            t.status = r.chance(0.9) ? .done : .wontDo
            let ago = r.int(0..<730)
            t.completedAt = perfNowMs - ago * day - r.int(0..<day)
            if r.chance(0.8) { t.dueDate = perfToday - (ago + r.int(0..<5)) }
        } else {
            if r.chance(0.65) {
                t.dueDate = perfToday + r.int(-30..<61)
                if r.chance(0.4) {
                    t.dueTime = r.int(7..<22) * 60 + r.pick([0, 15, 30, 45])
                    t.reminders = r.chance(0.7) ? [0, -15] : []
                    if r.chance(0.15) { t.duration = r.pick([30, 60, 90, 120]) }
                } else if r.chance(0.1) {
                    t.duration = r.int(2..<5) * minutesPerDay
                }
                if r.chance(0.1) { t.repeatRule = r.pick(repeats) }
            }
            if r.chance(0.02) { t.pinnedAt = perfNowMs - r.int(0..<(30 * day)) }
        }
        if r.chance(0.01) { t.trashedAt = perfNowMs - r.int(0..<(30 * day)) }
        tasks.append(t)
    }

    var items: [ChecklistItem] = []
    items.reserveCapacity(subtasks)
    for k in 0..<subtasks {
        // Five per task on 1600 tasks, open and finished alike.
        let owner = tasks[(k / 5) * 3 % taskCount]
        items.append(ChecklistItem(id: "c\(k)", taskId: owner.id, title: "\(r.pick(verbs))\(r.pick(nouns))",
                                   done: owner.status != .open || r.chance(0.4), sortOrder: Double(k % 5), dirty: false))
    }

    let filters = [
        TaskFilter(id: "f0", name: "本周重要", rule: #"{"match":"all","conditions":[{"field":"date","values":["thisWeek"]},{"field":"priority","values":["high"]}]}"#, sortOrder: 0),
        TaskFilter(id: "f1", name: "工作和会议", rule: #"{"match":"all","conditions":[{"field":"list","values":["l0","l5","l6"]},{"field":"tag","values":["会议","周报"]}]}"#, sortOrder: 1),
        TaskFilter(id: "f2", name: "没日期的", rule: #"{"match":"all","conditions":[{"field":"date","values":["none"]}]}"#, sortOrder: 2),
        TaskFilter(id: "f3", name: "关键词", rule: #"{"match":"any","conditions":[{"field":"keyword","values":["报销"]},{"field":"priority","values":["high"]}]}"#, sortOrder: 3),
        TaskFilter(id: "f4", name: "过期和今天", rule: #"{"match":"all","conditions":[{"field":"date","values":["overdue","today"]}]}"#, sortOrder: 4),
    ]
    return TaskData(lists: lists, tasks: tasks, checklistItems: items, sections: sections, filters: filters)
}

/// Writes `data` into `db` in one transaction.
nonisolated func insertPerfData(_ data: TaskData, into db: AppDatabase) async throws {
    try await db.writer.write { d in
        for l in data.lists { try l.insert(d) }
        for s in data.sections { try s.insert(d) }
        for t in data.tasks { try t.insert(d) }
        for c in data.checklistItems { try c.insert(d) }
        for f in data.filters { try f.insert(d) }
    }
}

/// Runs `body` `runs` times (after one warm-up) and returns the median in
/// milliseconds; prints `PERF <name>: median … min …`.
@discardableResult
func perfTime(_ name: String, runs: Int = 3, _ body: () throws -> Void) rethrows -> Double {
    let clock = ContinuousClock()
    try body()
    var times: [Double] = []
    for _ in 0..<runs {
        let d = try clock.measure(body)
        times.append(Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000)
    }
    times.sort()
    let median = times[times.count / 2]
    print(String(format: "PERF %@: median %.2f ms, min %.2f ms", name, median, times[0]))
    return median
}

/// The async kind (database reads, observation round trips).
@discardableResult
func perfTimeAsync(_ name: String, runs: Int = 3, _ body: () async throws -> Void) async rethrows -> Double {
    let clock = ContinuousClock()
    try await body()
    var times: [Double] = []
    for _ in 0..<runs {
        let start = clock.now
        try await body()
        let d = clock.now - start
        times.append(Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000)
    }
    times.sort()
    let median = times[times.count / 2]
    print(String(format: "PERF %@: median %.2f ms, min %.2f ms", name, median, times[0]))
    return median
}
