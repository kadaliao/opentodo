// Ported from `app/test/filters_test.dart`, plus byte-for-byte checks of
// the stored JSON against what the Dart version writes.

import Testing
@testable import OpenTodoDomain

private func rule(_ conditions: [FilterCondition], all: Bool = true) -> FilterRule {
    FilterRule(matchAll: all, conditions: conditions)
}

private func cond(_ f: FilterField, _ values: [String], exclude: Bool = false) -> FilterCondition {
    FilterCondition(f, values, exclude: exclude)
}

private func titles(_ r: FilterRule, _ tasks: [TodoTask]) -> [String] {
    tasks.filter(r.matcher(testNow)).map(\.title)
}

@Suite("filters")
struct FiltersTests {
    // testNow is Sunday 2026-11-15, 10:00; the week runs Monday 11-09 to 11-15.
    let tasks = [
        makeTask("过期", due: "2026-11-10", priority: .high, tags: ["工作"]),
        makeTask("早上", listId: "work", due: "2026-11-15", time: 9 * 60, tags: ["工作", "会议"]),
        makeTask("今天", due: "2026-11-15", priority: .medium),
        makeTask("明天", listId: "work", due: "2026-11-16", priority: .high),
        makeTask("下周三", due: "2026-11-18", content: "准备季度周报"),
        makeTask("下月", listId: "home", due: "2026-12-02", priority: .low),
        makeTask("没日期", listId: "home", tags: ["购物"]),
        makeTask("跨周末", due: "2026-11-14", duration: 3 * 1440), // Sat–Mon
        makeTask("垃圾", due: "2026-11-15", trashedAt: 1),
    ]

    @Test("an empty rule takes every task that is not in the trash")
    func emptyRule() {
        #expect(titles(FilterRule(), tasks).count == 8)
        // A condition with nothing chosen is left out.
        #expect(titles(rule([cond(.list, [])]), tasks).count == 8)
    }

    @Test("lists, tags and priorities")
    func fields() {
        #expect(titles(rule([cond(.list, ["work", "home"])]), tasks) == ["早上", "明天", "下月", "没日期"])
        #expect(titles(rule([cond(.tag, ["工作"])]), tasks) == ["过期", "早上"])
        #expect(titles(rule([cond(.tag, [noTag])]), tasks) == ["今天", "明天", "下周三", "下月", "跨周末"])
        #expect(titles(rule([cond(.priority, ["high", "medium"])]), tasks) == ["过期", "今天", "明天"])
        #expect(titles(rule([cond(.priority, ["none"])]), tasks) == ["早上", "下周三", "没日期", "跨周末"])
    }

    @Test("dates: a span is on every day it covers")
    func dates() {
        func on(_ v: [String]) -> [String] { titles(rule([cond(.date, v)]), tasks) }
        #expect(on(["overdue"]) == ["过期", "早上"]) // 9:00 has passed
        #expect(on(["today"]) == ["早上", "今天", "跨周末"])
        #expect(on(["tomorrow"]) == ["明天", "跨周末"])
        #expect(on(["thisWeek"]) == ["过期", "早上", "今天", "跨周末"])
        #expect(on(["nextWeek"]) == ["明天", "下周三", "跨周末"])
        #expect(on(["next7"]) == ["早上", "今天", "明天", "下周三", "跨周末"])
        #expect(on(["thisMonth"]) == ["过期", "早上", "今天", "明天", "下周三", "跨周末"])
        #expect(on(["none"]) == ["没日期"])
        #expect(on(["none", "tomorrow"]) == ["明天", "没日期", "跨周末"])
    }

    @Test("keywords look in the title and the notes, ignoring case")
    func keywords() {
        #expect(titles(rule([cond(.keyword, ["周报"])]), tasks) == ["下周三"])
        #expect(titles(rule([cond(.keyword, ["  "])]), tasks).count == 8)
        let english = [makeTask("Weekly Report")]
        #expect(titles(rule([cond(.keyword, ["report"])]), english) == ["Weekly Report"])
    }

    @Test("all, any, and excluding")
    func allAnyExclude() {
        let work = cond(.list, ["work"])
        let high = cond(.priority, ["high"])
        #expect(titles(rule([work, high]), tasks) == ["明天"])
        #expect(titles(rule([work, high], all: false), tasks) == ["过期", "早上", "明天"])
        #expect(titles(rule([cond(.tag, ["工作"], exclude: true), cond(.date, ["today"])]), tasks) == ["今天", "跨周末"])
    }

    @Test("JSON round trip keeps conditions from a newer version")
    func roundTrip() {
        let text = rule([cond(.list, ["inbox", "work"]), cond(.tag, [noTag], exclude: true)], all: false).encode()
        let back = FilterRule.parse(text)
        #expect(back.encode() == text)
        #expect(!back.matchAll)
        #expect(back.conditions[1].exclude)

        let future = FilterRule.parse(
            #"{"match":"all","conditions":[{"field":"assignee","values":["me"]},"#
                + #"{"field":"priority","values":["high"]}]}"#
        )
        #expect(!future.conditions[0].isKnown)
        // Left out when matching, kept when saving.
        #expect(titles(future, tasks) == ["过期", "明天"])
        #expect(future.encode().contains(#""assignee""#))
        #expect(!future.isSimple)

        #expect(FilterRule.parse("not json").conditions.isEmpty)
        #expect(FilterRule.parse("[]").conditions.isEmpty)
        #expect(FilterRule.parse(#"{"conditions":5}"#).conditions.isEmpty)
    }

    @Test("the simple form: one row per field, all included, joined by all")
    func simpleForm() {
        var r = FilterRule()
        #expect(r.isSimple)
        r = r.withValues(.priority, ["high"]).withValues(.list, ["work"])
        #expect(r.conditions.map(\.field) == [.list, .priority])
        #expect(r.valuesOf(.list) == ["work"])
        r = r.withValues(.list, [])
        #expect(r.conditions.map(\.field) == [.priority])
        #expect(r.isSimple)

        #expect(!rule([cond(.list, ["a"], exclude: true)]).isSimple)
        #expect(!rule([cond(.list, ["a"]), cond(.list, ["b"])]).isSimple)
        #expect(!rule([cond(.list, ["a"])], all: false).isSimple)
        // Empty rows don't count.
        #expect(rule([cond(.list, []), cond(.list, ["b"])]).isSimple)
    }

    @Test("a task added in a filter goes where the filter asks")
    func quickAddHints() {
        let today = Day(2026, 11, 15)
        let h = rule([
            cond(.list, ["work"]),
            cond(.tag, [noTag, "会议"]),
            cond(.date, ["tomorrow"]),
            cond(.priority, ["high"]),
        ]).quickAddHints(today)
        #expect(h.listId == "work")
        #expect(h.tag == "会议")
        #expect(h.date == Day(2026, 11, 16))
        #expect(h.priority == .high)

        let vague = rule([cond(.list, ["work", "home"]), cond(.date, ["thisWeek"])]).quickAddHints(today)
        #expect(vague.listId == nil)
        #expect(vague.date == nil)

        let d = quickAddDefaults(.filter("f"), today, [
            "f": rule([cond(.list, ["work"]), cond(.tag, ["会议"])]),
        ])
        #expect(d.listId == "work")
        #expect(d.tags == ["会议"])
        #expect(quickAddDefaults(.filter("gone"), today).listId == inboxListId)
    }

    @Test("a filter view groups by date, then later and undated; finished ones last")
    func filterView() {
        let rules = ["f": FilterRule()]
        let all = tasks + [
            makeTask("很久以后", due: "2027-03-01"),
            makeTask("做完了", due: "2026-11-15", status: .done, completedAt: 5),
        ]
        #expect(shape(buildSections(view: .filter("f"), tasks: all, lists: [:], now: testNow, filters: rules)) == [
            sec("已过期", ["过期"]),
            sec("今天, 周日", ["跨周末", "今天", "早上"]),
            sec("明天, 周一", ["明天"]),
            sec("11月18日, 周三", ["下周三"]),
            sec("以后", ["下月", "很久以后"]),
            sec("无日期", ["没日期"]),
            sec("已完成", ["做完了"]),
        ])
        #expect(openCount(.filter("f"), all, testNow, rules) == 9)
        // A filter that isn't there lists nothing.
        #expect(openCount(.filter("gone"), all, testNow, rules) == 0)
        #expect(viewTitle(.filter("gone"), [:]) == "过滤器")
    }

    @Test("describeValues")
    func describe() {
        #expect(describeValues(.date, [], lists: [:]) == "所有")
        #expect(describeValues(.date, ["today", "none"], lists: [:]) == "今天、无日期")
        #expect(describeValues(.list, ["inbox", "gone"], lists: [:]) == "收集箱、已删除的清单")
        #expect(describeValues(.tag, [noTag, "工作"], lists: [:]) == "无标签、工作")
        #expect(describeValues(.priority, ["high", "low"], lists: [:]) == "高、低")
    }

    // MARK: Not in the Dart tests: the stored text, byte for byte

    @Test("writes what the Dart version writes")
    func dartBytes() {
        // Known conditions in Dart's order and form; `exclude` only when set.
        #expect(rule([cond(.list, ["inbox"]), cond(.tag, ["工作", noTag], exclude: true)]).encode()
            == #"{"match":"all","conditions":[{"field":"list","values":["inbox"]},{"field":"tag","values":["工作",""],"exclude":true}]}"#)
        #expect(FilterRule().encode() == #"{"match":"all","conditions":[]}"#)
        #expect(rule([cond(.keyword, ["a\"b\\c\n\t\u{01}/é😀"])]).encode()
            == #"{"match":"all","conditions":[{"field":"keyword","values":["a\"b\\c\n\t\u0001/é😀"]}]}"#)
    }

    @Test("a condition from a newer version comes back exactly as it was")
    func unknownKeptVerbatim() {
        let unknown = #"{"field":"assignee","values":["me",{"z":1,"a":[1.5,2.0,-0.0,1e21,1E2,0.000001,1e-7,12345678901234567890,null,true,false]}],"exclude":false,"extra":"é\/"}"#
        let text = #"{"match":"any","conditions":["# + unknown + "]}"
        let r = FilterRule.parse(text)
        #expect(!r.conditions[0].isKnown)
        // Dart re-encodes numbers and escapes its own way.
        let expected = #"{"field":"assignee","values":["me",{"z":1,"a":[1.5,2.0,-0.0,1e+21,100.0,0.000001,1e-7,12345678901234567000.0,null,true,false]}],"exclude":false,"extra":"é/"}"#
        #expect(r.encode() == #"{"match":"any","conditions":["# + expected + "]}")
        // Saving again changes nothing.
        #expect(FilterRule.parse(r.encode()).encode() == r.encode())
    }

    @Test("a known condition and the rule keep only what Dart keeps")
    func knownTidied() {
        // Extra keys on a known condition, values that aren't strings, and
        // keys of the rule itself are dropped, as the Dart version does.
        let r = FilterRule.parse(#" {"version":2,"conditions":[{"exclude":false,"values":["a",3,"b"],"field":"list","x":1},7,{"field":"tag","values":"x"}]} "#)
        #expect(r.matchAll)
        #expect(r.conditions.count == 2)
        #expect(r.conditions[0] == cond(.list, ["a", "b"]))
        #expect(!r.conditions[1].isKnown) // values isn't a list
        #expect(r.encode()
            == #"{"match":"all","conditions":[{"field":"list","values":["a","b"]},{"field":"tag","values":"x"}]}"#)
        #expect(FilterRule.parse(#"{"match":"any","conditions":[],}"#).conditions.isEmpty) // not JSON
        #expect(FilterRule.parse(#"{"match":"any"}"#).matchAll == false)
    }

    @Test("tidy and copy")
    func tidyAndCopy() {
        let future = FilterRule.parse(#"{"conditions":[{"field":"new","values":[]},{"field":"list","values":[]}]}"#)
        #expect(future.tidy().conditions.count == 1)
        #expect(!future.tidy().conditions[0].isKnown)
        let c = cond(.list, ["a"]).copy(values: ["b"], exclude: true)
        #expect(c == cond(.list, ["b"], exclude: true))
    }
}
