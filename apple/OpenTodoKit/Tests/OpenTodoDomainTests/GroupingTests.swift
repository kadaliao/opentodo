// Ported from `app/test/grouping_test.dart`. Its last test (`dropInto`)
// runs through `TaskRepo` and belongs to the data layer.

import Testing
@testable import OpenTodoDomain

func list(_ id: String, _ name: String, _ order: Double = 0) -> TaskList {
    TaskList(id: id, name: name, sortOrder: order, dirty: false)
}

/// The kind of a section's target, as Dart's `runtimeType`.
func targetKind(_ t: GroupTarget?) -> String {
    switch t {
    case nil: "Null"
    case .section?: "SectionTarget"
    case .date?: "DateTarget"
    case .priority?: "PriorityTarget"
    case .list?: "ListTarget"
    case .tag?: "TagTarget"
    case .order?: "OrderTarget"
    }
}

@Suite("grouping")
struct GroupingTests {
    let tasks = [
        makeTask("过期", listId: "w", due: "2026-11-10", priority: .low),
        makeTask("今天", listId: "w", due: "2026-11-15", tags: ["家", "急"]),
        makeTask("后天", listId: "w", due: "2026-11-17", priority: .high, tags: ["工作"]),
        makeTask("下个月", listId: "w", due: "2026-12-20", priority: .high),
        makeTask("没日期", listId: "w", tags: ["急"]),
        makeTask("做完了", listId: "w", priority: .high, status: .done, completedAt: 1),
    ]

    func inList(_ g: TaskGrouping, _ sort: TaskSort? = nil) -> [TaskSection] {
        buildSections(view: .list("w"), tasks: tasks, lists: [:], now: testNow, grouping: g, sort: sort)
    }

    @Test("a list grouped by date, tag, priority or not at all")
    func groupings() {
        #expect(shape(inList(.date)) == [
            sec("已过期", ["过期"]),
            sec("今天, 周日", ["今天"]),
            sec("11月17日, 周二", ["后天"]),
            sec("以后", ["下个月"]),
            sec("无日期", ["没日期"]),
            sec("已完成", ["做完了"]),
        ])
        // Filed under the first tag; tags A to Z in pinyin (gong, ji, jia).
        #expect(shape(inList(.tag)) == [
            sec("工作", ["后天"]),
            sec("急", ["没日期"]),
            sec("家", ["今天"]),
            sec("无标签", ["下个月", "过期"]),
            sec("已完成", ["做完了"]),
        ])
        // Only the priorities that have tasks; finished ones in 已完成.
        #expect(shape(inList(.priority)) == [
            sec("高优先级", ["下个月", "后天"]),
            sec("低优先级", ["过期"]),
            sec("无优先级", ["没日期", "今天"]),
            sec("已完成", ["做完了"]),
        ])
        #expect(shape(inList(.none, .due)) == [
            sec(nil, ["过期", "今天", "后天", "下个月", "没日期"]),
            sec("已完成", ["做完了"]),
        ])
    }

    @Test("what a drop into each group does, and whether order counts")
    func drops() {
        let byDate = inList(.date)
        #expect(byDate.map { targetKind($0.target) } == [
            "Null", "DateTarget", "DateTarget", "Null", "DateTarget", "Null", // 已过期 and 以后 take nothing
        ])
        #expect(byDate[4].day == nil) // 无日期
        #expect(byDate[1].day == Day(2026, 11, 15))
        #expect(byDate.allSatisfy { $0.target == nil || $0.manualOrder }) // a list's default
        #expect(byDate.last!.finished)
        #expect(!inList(.date, .title).contains(where: { $0.manualOrder }))

        let none = inList(.none)
        #expect(none.first?.target == .order)
        // Not grouped and not in manual order: nothing to drop.
        #expect(inList(.none, .due).first?.target == nil)

        let byPriority = inList(.priority)
        #expect(byPriority.first?.target == .priority(.high))
    }

    @Test("a grouping or order a view does not offer falls back to its default")
    func fallBack() {
        // 今天 has no sections of its own, nor an order by hand.
        let today = buildSections(
            view: .smart(.today), tasks: tasks, lists: [:], now: testNow, grouping: .sections, sort: .manual
        )
        #expect(shape(today) == [
            sec("已过期", ["过期"]),
            sec("今天, 周日", ["今天"]),
        ])
        #expect(!groupingsFor(.tag("家")).contains(.tag))
        #expect(groupingsFor(.smart(.trash)).isEmpty)
        #expect(sortsFor(.smart(.completed)).isEmpty)
        #expect(sortsFor(.smart(.inbox)).first == .manual)
        #expect(sortsFor(.filter("f")).first == .due)
    }

    @Test("by list: the sidebar order, 收集箱 first, a list that is gone last")
    func byList() {
        let lists = ["b": list("b", "生活", 2), "a": list("a", "工作", 1)]
        let s = buildSections(
            view: .smart(.next7),
            tasks: [
                makeTask("生活的", listId: "b", due: "2026-11-15"),
                makeTask("没了的", listId: "gone", due: "2026-11-15"),
                makeTask("工作的", listId: "a", due: "2026-11-16"),
                makeTask("收集的", due: "2026-11-17"),
            ],
            lists: lists,
            now: testNow,
            grouping: .list
        )
        #expect(s.map(\.id) == ["list-inbox", "list-a", "list-b", "list-gone"])
        #expect(s.map { x -> String? in if case .list(let id)? = x.target { id } else { nil } } == ["inbox", "a", "b", nil])
        // A tag view groups by list by default.
        let tagged = buildSections(
            view: .tag("t"),
            tasks: [makeTask("甲", listId: "b", tags: ["t"]), makeTask("乙", listId: "a", tags: ["t"])],
            lists: lists,
            now: testNow
        )
        #expect(shape(tagged) == [sec("工作", ["乙"]), sec("生活", ["甲"])])
    }

    @Test("order by tag: first tag A to Z in pinyin, untagged last, then by date")
    func orderByTag() {
        let s = buildSections(
            view: .list("w"),
            tasks: [
                makeTask("无标签", listId: "w", due: "2026-11-15"),
                makeTask("b晚", listId: "w", due: "2026-11-20", tags: ["b"]),
                makeTask("急", listId: "w", tags: ["急"]),
                makeTask("b早", listId: "w", due: "2026-11-16", tags: ["b"]),
                makeTask("阿", listId: "w", tags: ["阿姨", "z"]),
            ],
            lists: [:],
            now: testNow,
            sort: .tag
        )
        #expect(s.count == 1)
        #expect(s[0].tasks.map(\.title) == ["阿", "b早", "b晚", "急", "无标签"])
    }

    @Test("a tag group swaps the tag a task was filed under")
    func retag() {
        #expect(GroupTarget.tag("乙").retag(["甲", "丙"]) == ["乙", "丙"])
        #expect(GroupTarget.tag("丙").retag(["甲", "丙"]) == ["丙"])
        #expect(GroupTarget.tag("乙").retag([]) == ["乙"])
        #expect(GroupTarget.tag(nil).retag(["甲", "丙"]).isEmpty)
        #expect(GroupTarget.tag("甲").has(makeTask("x", tags: ["甲", "乙"])))
        #expect(!GroupTarget.tag("乙").has(makeTask("x", tags: ["甲", "乙"])))
    }

    // Not in the Dart tests: the other targets' `has` and `takes`.
    @Test("what each target has and takes")
    func hasAndTakes() {
        let t = makeTask("x", listId: "w", due: "2026-11-15", priority: .medium, sectionId: "s")
        #expect(GroupTarget.section(listId: "w", sectionId: "s").has(t))
        #expect(!GroupTarget.section(listId: "w", sectionId: nil).has(t))
        #expect(GroupTarget.section(listId: "w", sectionId: nil).takes(t))
        #expect(!GroupTarget.section(listId: "v", sectionId: nil).takes(t))
        #expect(GroupTarget.date(Day(2026, 11, 15)).has(t) && !GroupTarget.date(nil).has(t))
        #expect(GroupTarget.priority(.medium).has(t) && GroupTarget.list("w").has(t) && GroupTarget.order.has(t))
        #expect(GroupTarget.list("v").takes(t))
    }
}
