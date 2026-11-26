// Swift-only additions to search and filters (roadmap “清单的后续”): pinyin
// in notes, recent searches, a filter's custom date range, and dragging
// filters into order in the sidebar.

import Testing
@testable import OpenTodoDomain

@Suite("search extras")
struct SearchExtrasTests {
    @Test("notes can be typed in pinyin too, and the snippet shows where")
    func pinyinInNotes() {
        let t = makeTask("report", content: "下周一前交季度周报给老板")
        let r = search("zb", tasks: [t])
        #expect(r.tasks.map(\.task.title) == ["report"])
        #expect(r.tasks[0].snippet == "下周一前交季度周报给老板")
        #expect(r.tasks[0].snippetRanges == [7..<9])
        // A long note is cut around the pinyin match.
        let long = makeTask("long", content: String(repeating: "啊", count: 30) + "周报" + String(repeating: "x", count: 80))
        let hit = search("zhoubao", tasks: [long]).tasks[0]
        #expect(hit.snippet!.hasPrefix("…"))
        #expect(hit.snippet!.hasSuffix("…"))
        #expect(hit.snippetRanges == [13..<15])
        // Matched as typed in the notes first; subtasks and tags stay as typed.
        #expect(search("zb", tasks: [makeTask("y", content: "zb 和 周报")]).tasks[0].snippet == "zb 和 周报")
        let items = ["s": [ChecklistItem(id: "i", taskId: "s", title: "周报模板")]]
        #expect(search("zb", tasks: [makeTask("s")], checklist: items).tasks.isEmpty)
        #expect(search("zb", tasks: [makeTask("g", tags: ["周报"])]).tasks.isEmpty)
        // Notes without Chinese don't take pinyin.
        #expect(search("zb", tasks: [makeTask("e", content: "zebra")]).tasks.isEmpty)
    }

    @Test("recent searches: newest first, no repeats, at most ten")
    func recent() {
        var r = RecentSearches()
        #expect(r.isEmpty)
        r = r.adding("周报").adding("  工作   计划 ").adding("   ").adding("Q3")
        #expect(r.queries == ["Q3", "工作 计划", "周报"])
        r = r.adding("周报").adding("q3")
        #expect(r.queries == ["q3", "周报", "工作 计划"])
        #expect(r.removing("周报 ").queries == ["q3", "工作 计划"])
        for i in 0..<15 { r = r.adding("词\(i)") }
        #expect(r.queries.count == RecentSearches.limit)
        #expect(r.queries.first == "词14")
        #expect(r.queries.last == "词5")
    }

    @Test("recent searches are stored as a JSON array; bad text reads as none")
    func recentStorage() {
        let r = RecentSearches(["周报", "a\"b"])
        #expect(r.encode() == #"["周报","a\"b"]"#)
        #expect(RecentSearches(json: r.encode()) == r)
        #expect(RecentSearches(json: nil).isEmpty)
        #expect(RecentSearches(json: "{").isEmpty)
        #expect(RecentSearches(json: #"{"a":1}"#).isEmpty)
        #expect(RecentSearches(json: #"["x", 3, "", "X", "y"]"#).queries == ["x", "y"])
    }

    @Test("a custom date range is stored as start~end and matched day by day")
    func customRange() {
        let range = FilterDateRange(Day("2026-11-20")!, Day("2026-11-16")!)
        #expect(range.value == "2026-11-16~2026-11-20")
        #expect(FilterDateRange(value: range.value) == range)
        for bad in ["today", "2026-11-16", "2026-11-16~", "2026-11-16~2026-13-01", "2026-1-6~2026-1-9", "a~b"] {
            #expect(FilterDateRange(value: bad) == nil, "\(bad)")
        }
        let tasks = [
            makeTask("before", due: "2026-11-15"),
            makeTask("first", due: "2026-11-16"),
            makeTask("last", due: "2026-11-20"),
            makeTask("after", due: "2026-11-21"),
            makeTask("span", due: "2026-11-13", duration: 4 * 1440), // 13th–17th
            makeTask("none"),
        ]
        let r = FilterRule(conditions: [FilterCondition(.date, [range.value])])
        #expect(tasks.filter(r.matcher(testNow)).map(\.title) == ["first", "last", "span"])
        // Alongside the fixed choices, any of them.
        let r2 = FilterRule(conditions: [FilterCondition(.date, [range.value, "none"])])
        #expect(tasks.filter(r2.matcher(testNow)).map(\.title) == ["first", "last", "span", "none"])
        // 不包含 turns it around.
        let r3 = FilterRule(conditions: [FilterCondition(.date, [range.value], exclude: true)])
        #expect(tasks.filter(r3.matcher(testNow)).map(\.title) == ["before", "after", "none"])
        // It survives a round trip through the stored JSON, and is simple.
        #expect(FilterRule.parse(r2.encode()) == r2)
        #expect(r2.isSimple)
    }

    @Test("a custom range reads as dates in the picker")
    func customRangeLabel() {
        let today = Day("2026-11-15")!
        let r = FilterDateRange(Day("2026-11-01")!, Day("2026-11-30")!)
        #expect(r.label(today: today) == "11月1日–11月30日")
        #expect(r.label() == "2026年11月1日–11月30日")
        #expect(FilterDateRange(Day("2026-12-28")!, Day("2027-01-03")!).label(today: today) == "2026年12月28日–2027年1月3日")
        #expect(FilterDateRange(today, today).label(today: today) == "11月15日")
        #expect(describeValues(.date, ["today", r.value], lists: [:], today: today) == "今天、11月1日–11月30日")
        // A value from a newer version still shows as written.
        #expect(describeValues(.date, ["someday"], lists: [:]) == "someday")
    }

    @Test("setting a condition's range replaces the one there, in its place")
    func settingRange() {
        let a = FilterDateRange(Day("2026-11-01")!, Day("2026-11-02")!)
        let b = FilterDateRange(Day("2026-12-01")!, Day("2026-12-02")!)
        let c = FilterCondition(.date, ["today", a.value, "none"])
        #expect(c.dateRange == a)
        #expect(c.values(settingRange: b) == ["today", b.value, "none"])
        #expect(c.values(settingRange: nil) == ["today", "none"])
        #expect(FilterCondition(.date, ["today"]).values(settingRange: b) == ["today", b.value])
        #expect(FilterCondition(.date, ["today"]).dateRange == nil)
        #expect(FilterCondition(.keyword, [a.value]).dateRange == nil)
    }

    @Test("dragging filters in the sidebar renumbers only the moved one")
    func filterMove() {
        func f(_ id: String, _ order: Double, created: Int = 0, deleted: Bool = false) -> TaskFilter {
            TaskFilter(id: id, name: id, sortOrder: order, createdAt: created, deletedAt: deleted ? 1 : nil)
        }
        let filters = [f("c", 3000), f("a", 1000), f("gone", 1500, deleted: true), f("b", 2000), f("b2", 2000, created: 5)]
        #expect(sortedFilters(filters).map(\.id) == ["a", "b", "b2", "c"])
        // c to the top: before a.
        #expect(planFilterMove(filters, moving: "c", to: 0) == ["c": 1000 - orderStep])
        // a to between b2 and c.
        #expect(planFilterMove(filters, moving: "a", to: 3) == ["a": 2500])
        // a to the end.
        #expect(planFilterMove(filters, moving: "a", to: 4) == ["a": 3000 + orderStep])
        // Where it already is, or not there at all: nothing.
        #expect(planFilterMove(filters, moving: "b", to: 1).isEmpty)
        #expect(planFilterMove(filters, moving: "b", to: 2).isEmpty)
        #expect(planFilterMove(filters, moving: "gone", to: 0).isEmpty)
        // b and b2 share a number: no room between them, so they're numbered
        // afresh and only the ones that changed come back.
        let plan = planFilterMove(filters, moving: "c", to: 2)
        #expect(plan["a"] == nil)
        #expect(plan["c"] != nil)
        let order = sortedFilters(filters.map { var x = $0; if let o = plan[x.id] { x.sortOrder = o }; return x }).map(\.id)
        #expect(order == ["a", "b", "c", "b2"])
    }
}
