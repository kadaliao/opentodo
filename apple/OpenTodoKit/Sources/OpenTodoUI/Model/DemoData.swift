// `-OTSeed demo`: a believable week of someone's tasks, dated around
// `today` so the smart lists always have something in them, written
// through `TaskRepo` like any other change — into whatever database the
// app opened (screenshots use a fresh file, tests an in-memory one). Ids
// are stable so routes can name them:
//
//     lists     work 工作 · life 生活 · shopping 购物 · reading 读书 · fitness 健身
//     tasks     report (今天下午, 高, 子任务, 提醒) · standup (今天, 每周, 时间段)
//               review / invoice (过期) · slides (明天, 置顶) · okr · call (收集箱)
//               milk (今天, 子任务) · rent (每月) · run (今天已完成) · old (垃圾桶) …
//     filter    important-week 本周的重要工作
//
// e.g. `-OTOpen list:work`, `-OTOpen task:report`.
//
// `make(today:now:)` gives the same records as plain values, without a
// database, for debug screens and previews that only need something to
// draw (`seed` writes exactly these).

import Foundation
import OpenTodoData
import OpenTodoDomain

public enum DemoData {
    /// Writes the demo into `repo`'s database unless it already has tasks.
    /// `now` is the moment the completion times count back from.
    public static func seed(_ repo: TaskRepo, now: LocalDateTime) async throws {
        if try await !repo.database.observeTasks().first().isEmpty { return }
        let d = make(today: now.day, now: now, timeZone: repo.timeZone)
        for l in d.lists { try await repo.addList(l.name, emoji: l.emoji, id: l.id) }
        for s in d.sections { try await repo.addSection(s.listId, s.name, id: s.id) }
        for t in d.tasks {
            try await repo.addTask(
                id: t.id, title: t.title, listId: t.listId, sectionId: t.sectionId, dueDate: t.dueDate,
                dueTime: t.dueTime, duration: t.duration, tags: t.tags, priority: t.priority,
                reminders: t.reminders, repeatRule: t.repeatRule)
            if !t.content.isEmpty { try await repo.setContent(t.id, t.content) }
            for item in d.checklistItems where item.taskId == t.id {
                let id = try await repo.addChecklistItem(t.id, item.title)
                if item.done { try await repo.updateChecklistItem(id, done: true) }
            }
            if t.pinnedAt != nil { try await repo.setPinned(t.id, true) }
            if t.trashedAt != nil { try await repo.trashTask(t.id) }
            try await repo.updateTask(t.id) {
                $0.sortOrder = t.sortOrder
                $0.createdAt = t.createdAt
                $0.status = t.status
                $0.completedAt = t.completedAt
            }
        }
        for f in d.filters { try await repo.addFilter(f.name, f.rule, id: f.id) }
    }

    /// The demo as plain records, dated around `today`.
    public static func make(today: Day, now: LocalDateTime, timeZone: TimeZone = .current) -> TaskData {
        let nowMs = Int(now.date(in: timeZone).timeIntervalSince1970 * 1000)
        let hour = 3_600_000
        var tasks: [TodoTask] = []
        var items: [ChecklistItem] = []

        func task(_ id: String, _ title: String, list: String = inboxListId, section: String? = nil,
                  due: Int? = nil, time: (Int, Int)? = nil, duration: Int? = nil, priority: Priority = .none,
                  tags: [String] = [], notes: String = "", reminders: [Int] = [], rule: String? = nil,
                  pinned: Bool = false, doneHoursAgo: Int? = nil, trashed: Bool = false,
                  checklist: [(String, Bool)] = []) {
            tasks.append(TodoTask(
                id: id, listId: list, sectionId: section, title: title, content: notes, priority: priority,
                dueDate: due.map { today + $0 }, dueTime: time.map { $0.0 * 60 + $0.1 },
                duration: duration.map { normalizeDuration(time.map { $0.0 * 60 + $0.1 }, $0) } ?? nil,
                tags: tags, status: doneHoursAgo == nil ? .open : .done,
                completedAt: doneHoursAgo.map { nowMs - $0 * hour }, reminders: due == nil ? [] : reminders,
                repeatRule: due == nil ? nil : rule, pinnedAt: pinned ? nowMs - 48 * hour : nil,
                trashedAt: trashed ? nowMs - 30 * hour : nil, sortOrder: Double(tasks.count + 1) * 1024,
                createdAt: nowMs - 7 * 24 * hour, updatedAt: nowMs - hour))
            for (i, (title, done)) in checklist.enumerated() {
                items.append(ChecklistItem(id: "\(id)-\(i + 1)", taskId: id, title: title, done: done,
                                           sortOrder: Double(i + 1) * 1024, createdAt: nowMs, updatedAt: nowMs))
            }
        }

        // 收集箱
        task("call", "给物业打电话问停车位的事")
        task("idea", "把读书笔记整理成一篇文章", tags: ["想法"])
        task("trip", "订春节回家的高铁票", priority: .high, tags: ["出行"],
                       notes: "开售日是出发前 15 天，提前设好闹钟。")
        // 工作
        task("report", "写第四季度工作总结", list: "work", section: "work-doing", due: 0, time: (15, 0),
                       priority: .high, tags: ["工作"], notes: "重点写两个上线的项目和明年的计划，周五前发给主管。",
                       reminders: [-30],
                       checklist: [("列出今年上线的项目", true), ("收集各项目的数据", true), ("写问题和教训", false),
                                   ("写明年的计划", false), ("请同事看一遍", false)])
        task("standup", "部门周会", list: "work", section: "work-doing", due: 0, time: (10, 0), duration: 60,
                       priority: .medium, reminders: [-5], rule: "FREQ=WEEKLY;BYDAY=\(weekdayCode(today))")
        task("review", "评审设计稿的第二版", list: "work", section: "work-doing", due: -2, priority: .high,
                       tags: ["工作"])
        task("invoice", "报销十一月的差旅费", list: "work", section: "work-doing", due: -1, time: (18, 0),
                       priority: .medium, tags: ["财务"], reminders: [0])
        task("slides", "做季度汇报的幻灯片", list: "work", section: "work-doing", due: 1, time: (14, 0),
                       priority: .medium, tags: ["工作"], pinned: true,
                       checklist: [("确定大纲", false), ("做图表", false)])
        task("okr", "起草明年的 OKR", list: "work", section: "work-later", due: 3, priority: .low)
        task("onboarding", "给新同事准备入职资料", list: "work", section: "work-later")
        task("email", "回复客户关于报价的邮件", list: "work", section: "work-doing", due: 0, priority: .medium,
                       doneHoursAgo: 2)
        // 生活
        task("plants", "给阳台的花浇水", list: "life", due: 0, rule: "FREQ=DAILY;INTERVAL=3")
        task("dentist", "看牙医（洗牙）", list: "life", due: 2, time: (9, 30), priority: .medium,
                       reminders: [-60])
        task("rent", "交房租", list: "life", due: 5, priority: .high, tags: ["财务"],
                       reminders: [540], rule: "FREQ=MONTHLY;BYMONTHDAY=\((today + 5).day)")
        task("dinner", "周末陪爸妈吃饭", list: "life", due: 4, time: (18, 30), tags: ["家"])
        task("parcel", "取快递", list: "life", due: -1, doneHoursAgo: 20)
        // 购物
        task("milk", "超市：牛奶、鸡蛋、面包", list: "shopping", due: 0, time: (19, 0),
                       checklist: [("牛奶", true), ("鸡蛋", false), ("全麦面包", false)])
        task("battery", "买 5 号电池", list: "shopping")
        task("gift", "给小侄子挑生日礼物", list: "shopping", due: 6, priority: .low, tags: ["家"])
        // 读书
        task("book", "读完《置身事内》第二部分", list: "reading", due: 6, priority: .low, tags: ["读书"])
        task("notes", "整理上个月的读书摘录", list: "reading", doneHoursAgo: 30)
        // 健身
        task("run", "晨跑 5 公里", list: "fitness", due: 0, time: (7, 0), rule: "FREQ=DAILY", doneHoursAgo: 3)
        task("gym", "健身房：练腿", list: "fitness", due: 1, time: (19, 30), duration: 90,
                       rule: "FREQ=WEEKLY;BYDAY=\(weekdayCode(today + 1))")
        // 垃圾桶
        task("old", "预约汽车保养", list: "life", trashed: true)

        let lists = [("work", "工作", "💼"), ("life", "生活", "🏠"), ("shopping", "购物", "🛒"),
                     ("reading", "读书", "📚"), ("fitness", "健身", "🏃")].enumerated().map { i, l in
            TaskList(id: l.0, name: l.1, emoji: l.2, sortOrder: Double(i + 1) * 1024, createdAt: nowMs, updatedAt: nowMs)
        }
        let sections = [
            ListSection(id: "work-doing", listId: "work", name: "进行中", sortOrder: 0, createdAt: nowMs, updatedAt: nowMs),
            ListSection(id: "work-later", listId: "work", name: "待安排", sortOrder: 1024, createdAt: nowMs, updatedAt: nowMs),
        ]
        let filters = [TaskFilter(
            id: "important-week", name: "本周的重要工作",
            rule: #"{"match":"all","conditions":[{"field":"date","values":["thisWeek"]},{"field":"priority","values":["high"]},{"field":"list","values":["work"]}]}"#,
            sortOrder: 1024, createdAt: nowMs, updatedAt: nowMs)]
        return TaskData(lists: lists, tasks: tasks, checklistItems: items, sections: sections, filters: filters)
    }

    private static func weekdayCode(_ d: Day) -> String {
        ["MO", "TU", "WE", "TH", "FR", "SA", "SU"][d.weekday - 1]
    }
}
