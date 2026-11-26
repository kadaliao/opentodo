// The flows of `app/test/search_filter_ui_test.dart`, run against the
// models behind the search panel and the filter editor (the views only show
// them; the database side is the caller's), plus the keyboard and editing
// rules the views rely on.

import Foundation
import OpenTodoDomain
import Testing
@testable import OpenTodoUI

private let now = LocalDateTime(2026, 11, 15, 10)
private let work = TaskList(id: "work", name: "工作", emoji: "💼", sortOrder: 1, dirty: false)
private let home = TaskList(id: "home", name: "家里", emoji: "🏠", sortOrder: 2, dirty: false)

private func task(_ title: String, list: String = inboxListId, priority: Priority = .none, updated: Int = 0) -> TodoTask {
    TodoTask(id: title, listId: list, title: title, priority: priority, updatedAt: updated, dirty: false)
}

/// Two lists and a few tasks: 写周报 (工作, high), 整理桌面 (工作), 交房租
/// (家里, high), 读书 (收集箱), and 开会 whose subtask mentions 周报.
private func demo() -> SearchData {
    let tasks = [
        task("写周报", list: work.id, priority: .high, updated: 5),
        task("整理桌面", list: work.id, updated: 4),
        task("交房租", list: home.id, priority: .high, updated: 3),
        task("读书", updated: 2),
        task("开会", list: home.id, updated: 1),
    ]
    return SearchData(
        tasks: tasks,
        checklist: ["开会": [ChecklistItem(id: "c", taskId: "开会", title: "带上周报模板", dirty: false)]],
        lists: [work, home]
    )
}

@Suite("search and filter UI")
struct SearchFilterUITests {
    @Test("desktop: make a filter, add to it, change it, delete it")
    func makeChangeDelete() throws {
        var tasks = demo().tasks
        var m = FilterEditorModel()
        #expect(m.title == "添加过滤器")
        #expect(!m.advanced)
        #expect(m.matchingCount(tasks, now: now) == 5)
        #expect(FilterEditorModel.countText(5) == "现在有 5 个未完成任务符合条件")
        // 保存 waits for a name.
        #expect(!m.canSave)
        #expect(m.result() == nil)
        m.name = "重要工作"
        #expect(m.canSave)

        // 清单: tick 工作 in the menu.
        let options = filterValueOptions(.list, values: m.simpleValues(.list), lists: [work, home], tags: [])
        #expect(options.map(\.label) == ["收集箱", "💼 工作", "🏠 家里"])
        m.setSimpleValues(.list, toggling(work.id, in: m.simpleValues(.list), options: options))
        let context = FilterPickerContext(lists: [work, home], tags: [], today: now.day)
        #expect(context.summary(.list, m.simpleValues(.list)) == "工作") // the picker's summary
        #expect(m.matchingCount(tasks, now: now) == 2)
        m.setPriority("high", on: true)
        #expect(m.matchingCount(tasks, now: now) == 1)
        let saved = try #require(m.result())
        #expect(saved.name == "重要工作")
        #expect(saved.rule.encode() == #"{"match":"all","conditions":[{"field":"list","values":["work"]},{"field":"priority","values":["high"]}]}"#)

        // The filter shows 写周报 and not 整理桌面.
        let filter = TaskFilter(id: "f", name: saved.name, rule: saved.rule.encode(), dirty: false)
        let rules = ["f": FilterRule.parse(filter.rule)]
        #expect(tasks.filter(viewMatcher(.filter("f"), now, rules)).map(\.title) == ["写周报"])

        // A task added here gets the filter's list and priority.
        let hints = quickAddDefaults(.filter("f"), now.day, rules)
        #expect(hints.listId == work.id)
        #expect(hints.priority == .high)
        tasks.append(task("准备材料", list: work.id, priority: .high))

        // In 高级, turn the priority around: 工作 tasks that are not high.
        var e = FilterEditorModel(filter: filter)
        #expect(e.title == "编辑过滤器")
        #expect(e.name == "重要工作")
        e.setAdvanced(true)
        #expect(e.rule.conditions.map(\.exclude) == [false, false]) // two rows of 包含
        e.setExclude(at: 1, true)
        #expect(e.matchingCount(tasks, now: now) == 1)
        // The simple form can't show that.
        #expect(!e.canSimple)
        e.setAdvanced(false)
        #expect(e.advanced)
        let changed = try #require(e.result())
        let changedRules = ["f": changed.rule]
        #expect(tasks.filter(viewMatcher(.filter("f"), now, changedRules)).map(\.title) == ["整理桌面"])

        // Delete it: the view goes back to 今天.
        #expect(viewAfterDeletingFilter("f", selected: .filter("f")) == .smart(.today))
    }

    @Test("a filter deleted elsewhere while on screen goes back to 今天")
    func deletedElsewhere() {
        #expect(viewAfterDeletingFilter("f", selected: .filter("f")) == .smart(.today))
        #expect(viewAfterDeletingFilter("f", selected: .filter("g")) == .filter("g"))
        #expect(viewAfterDeletingFilter("f", selected: .list("work")) == .list("work"))
    }

    @Test("desktop: ⌘F searches; arrows and return open a task")
    func searchArrowsReturn() {
        let data = demo()
        let start = SearchModel(query: "", data: data)
        #expect(start.phase == .start)
        #expect(start.entries.isEmpty)

        let m = SearchModel(query: "周报", data: data)
        #expect(m.phase == .results)
        #expect(m.entries.map(\.id) == ["task:写周报", "task:开会"])
        guard case .task(let meetingHit) = m.entries[1] else { Issue.record(); return }
        #expect(meetingHit.snippet == "☐ 带上周报模板") // found in a subtask

        // ↓ then Return opens 开会, in a view that lists it.
        var cursor = SearchCursor()
        #expect(cursor.active(in: m) == 0)
        cursor.move(1, in: m)
        let active = cursor.active(in: m)!
        guard case .task(let opened)? = m.entries[active].target else { Issue.record(); return }
        #expect(opened.title == "开会")
        #expect(viewForTask(opened, .smart(.today), now) == .list(home.id))

        // A list opens as a view.
        let lists = SearchModel(query: "工作", data: data)
        #expect(lists.sections.map(\.title) == ["清单"])
        #expect(lists.entries.first?.target == .view(.list(work.id)))

        // Nothing found.
        let none = SearchModel(query: "火星", data: data)
        #expect(none.phase == .noResults)
        #expect(none.noResultsTitle == "没有找到“火星”")
    }

    @Test("phone: search is a page; a task opens as its own page")
    func phone() {
        let m = SearchModel(query: "房租", data: demo())
        #expect(m.entries.map(\.id) == ["task:交房租"])
        guard case .task(let t)? = m.entries.first?.target else { Issue.record(); return }
        #expect(viewForTask(t, .smart(.today), now) == .list(home.id))
    }

    // MARK: Search panel details

    @Test("results come as lists, filters, tags, tasks; at most 100 tasks with a note")
    func sections() {
        var data = demo()
        data.tags = ["周会"]
        data.filters = [TaskFilter(id: "f", name: "周报筛选", dirty: false)]
        data.lists.append(TaskList(id: "w", name: "周计划", dirty: false))
        data.tasks += (0..<120).map { task("周 \($0)") }
        let m = SearchModel(query: "周", data: data)
        #expect(m.sections.map(\.title) == ["清单", "过滤器", "标签", "任务"])
        #expect(m.sections.map(\.start) == [0, 1, 2, 3])
        #expect(m.entries.count == 103)
        #expect(m.moreTasksNote == "还有 22 个任务，多输几个字缩小范围")
        #expect(SearchModel(query: "写", data: demo()).moreTasksNote == nil)
    }

    @Test("the arrows stop at either end; typing goes back to the first result")
    func cursor() {
        let m = SearchModel(query: "周报", data: demo())
        var c = SearchCursor()
        c.move(-1, in: m)
        #expect(c.active(in: m) == 0)
        c.move(1, in: m)
        c.move(1, in: m)
        c.move(1, in: m)
        #expect(c.active(in: m) == 1)
        // Fewer results after more typing: still on one of them.
        let fewer = SearchModel(query: "写周报", data: demo())
        #expect(c.active(in: fewer) == 0)
        c.reset()
        #expect(c.active(in: m) == 0)
        // Nothing to move through.
        let none = SearchModel(query: "火星", data: demo())
        c.move(1, in: none)
        #expect(c.active(in: none) == nil)
    }

    @Test("recent searches show before typing; arrows pick one, choosing it types it")
    func recent() {
        let recent = RecentSearches(["房租", "周报"])
        let m = SearchModel(query: "", data: demo(), recent: recent)
        #expect(m.phase == .start)
        #expect(m.sections.map(\.title) == ["最近搜索"])
        #expect(m.entries == [.recent("房租"), .recent("周报")])
        #expect(m.entries.allSatisfy { $0.target == nil })
        var c = SearchCursor()
        #expect(c.active(in: m) == nil) // nothing highlighted until an arrow is pressed
        c.move(1, in: m)
        #expect(c.active(in: m) == 0)
        // Only opening a result remembers the query.
        #expect(recentAfterOpening(.recent("周报"), query: "", recent: recent) == recent)
        let hit = SearchModel(query: "写 ", data: demo()).entries[0]
        #expect(recentAfterOpening(hit, query: "写 ", recent: recent).queries == ["写", "房租", "周报"])
        // Typing hides them.
        #expect(SearchModel(query: "房", data: demo(), recent: recent).entries.allSatisfy { $0.target != nil })
    }

    @Test("pinyin still being composed isn't searched for")
    func composing() {
        #expect(committedText("周报zhou", marked: NSRange(location: 2, length: 4)) == "周报")
        #expect(committedText("a zh b", marked: NSRange(location: 2, length: 2)) == "a  b")
        #expect(committedText("周报", marked: nil) == "周报")
        #expect(committedText("周报", marked: NSRange(location: NSNotFound, length: 0)) == "周报")
        #expect(committedText("周报", marked: NSRange(location: 1, length: 5)) == "周报") // stale range
        // An emoji before the composed part counts as two UTF-16 units.
        #expect(committedText("😀xie", marked: NSRange(location: 2, length: 3)) == "😀")
    }

    @Test("highlighting marks the ranges and skips any that don't fit")
    func highlight() {
        let s = highlighted("写周报", [1..<3], mark: .yellow)
        #expect(String(s.characters) == "写周报")
        #expect(s.runs.count == 2)
        let broken = highlighted("😀a", [1..<2, 0..<9], mark: .yellow)
        #expect(String(broken.characters) == "😀a")
        #expect(broken.runs.count == 1)
    }

    // MARK: Filter editor details

    @Test("a rule 普通 can't show opens in 高级; switching drops empty rows")
    func modes() {
        let advanced = TaskFilter(id: "a", name: "x", rule: FilterRule(matchAll: false, conditions: [FilterCondition(.list, ["work"])]).encode())
        #expect(FilterEditorModel(filter: advanced).advanced)
        #expect(!FilterEditorModel(filter: TaskFilter(id: "b", name: "y", rule: "{}")).advanced)
        #expect(!FilterEditorModel(filter: TaskFilter(id: "c", name: "z", rule: "not json")).advanced)

        var m = FilterEditorModel()
        m.setAdvanced(true)
        #expect(m.rule.conditions == [FilterCondition(.list, [])]) // one empty 清单 row
        m.addCondition()
        m.addCondition()
        #expect(m.rule.conditions.map(\.field) == [.list, .tag, .date])
        m.setValues(at: 1, ["工作"])
        #expect(m.canSimple)
        m.setAdvanced(false)
        #expect(!m.advanced)
        #expect(m.rule.conditions == [FilterCondition(.tag, ["工作"])])
    }

    @Test("advanced rows: another field starts afresh, rows keep their ids")
    func rows() {
        var m = FilterEditorModel()
        m.setAdvanced(true)
        m.setValues(at: 0, ["work"])
        m.setExclude(at: 0, true)
        m.setField(at: 0, .priority)
        #expect(m.rule.conditions == [FilterCondition(.priority, [], exclude: true)])
        m.setField(at: 0, .priority) // the same: nothing changes
        for _ in 0..<5 { m.addCondition() }
        // Every field used: the next is 清单 again.
        #expect(m.rule.conditions.map(\.field) == [.priority, .list, .tag, .date, .keyword, .list])
        let keys = m.rowKeys
        #expect(Set(keys).count == keys.count)
        m.removeCondition(at: 1)
        #expect(m.rowKeys == [keys[0]] + keys[2...])
        m.setKeyword(at: 3, "  周报 ")
        m.setMatchAll(false)
        let r = FilterEditorModel(filter: nil).result()
        #expect(r == nil)
        m.name = "  名字 "
        let saved = m.result()!
        #expect(saved.name == "名字")
        // Empty rows left out, keyword trimmed.
        #expect(saved.rule == FilterRule(matchAll: false, conditions: [FilterCondition(.keyword, ["周报"])]))
    }

    @Test("a condition from a newer version shows, can be removed, saves as it was")
    func unknown() {
        let stored = #"{"match":"all","conditions":[{"field":"place","values":["office"]},{"field":"list","values":["work"]}]}"#
        var m = FilterEditorModel(filter: TaskFilter(id: "x", name: "新", rule: stored))
        #expect(m.advanced)
        #expect(!m.canSimple)
        #expect(!m.rule.conditions[0].isKnown)
        m.setValues(at: 0, ["home"]) // can't be edited
        #expect(m.result()!.rule.encode() == stored)
        m.removeCondition(at: 0)
        #expect(m.canSimple)
    }

    @Test("simple form: keyword and priority chips")
    func simple() {
        var m = FilterEditorModel()
        m.setSimpleKeyword("周报 ")
        #expect(m.simpleKeyword == "周报 ")
        m.setSimpleKeyword("   ")
        #expect(m.simpleValues(.keyword).isEmpty)
        m.setPriority("low", on: true)
        m.setPriority("high", on: true)
        #expect(m.simpleValues(.priority) == ["high", "low"])
        m.setPriority("high", on: false)
        #expect(m.simpleValues(.priority) == ["low"])
        m.setSimpleValues(.priority, []) // 所有
        #expect(m.rule.conditions.isEmpty)
    }

    @Test("value choices: a deleted list or a gone tag stays to be unticked")
    func options() {
        let gone = TaskList(id: "old", name: "旧", sortOrder: 3, deletedAt: 1)
        let o = filterValueOptions(.list, values: ["old", "missing", "work"], lists: [work, gone], tags: [])
        #expect(o.map(\.label) == ["收集箱", "💼 工作", "已删除的清单", "已删除的清单"])
        #expect(toggling("old", in: ["old", "work"], options: o) == ["work"])
        let tags = filterValueOptions(.tag, values: ["旧标签"], lists: [], tags: ["工作"])
        #expect(tags.map(\.label) == ["无标签", "工作", "旧标签"])
        let range = FilterDateRange(Day(2026, 11, 1), Day(2026, 11, 3)).value
        let dates = filterValueOptions(.date, values: ["someday", range], lists: [], tags: [])
        #expect(dates.map(\.value) == DateChoice.allCases.map(\.rawValue) + ["someday"])
        // Ticking keeps the order of the choices; the custom range stays.
        #expect(toggling("today", in: [range, "none"], options: dates) == ["today", "none", range])
        #expect(filterValueOptions(.priority, values: [], lists: [], tags: []).map(\.label) == ["高", "中", "低", "无"])
        #expect(filterValueOptions(.keyword, values: ["x"], lists: [], tags: []).map(\.label) == ["“x”"])
    }

    @Test("the rule editor on its own: starts from a rule, hands back the saved form")
    func ruleOnly() {
        var m = FilterEditorModel(rule: FilterRule(conditions: [FilterCondition(.priority, ["high"])]))
        #expect(!m.advanced)
        #expect(m.name.isEmpty && m.filterId == nil)
        m.setAdvanced(true)
        m.addCondition()
        m.setField(at: 1, .keyword)
        m.setKeyword(at: 1, " 周报 ")
        #expect(m.savedRule == FilterRule(conditions: [FilterCondition(.priority, ["high"]), FilterCondition(.keyword, ["周报"])]))
        m.addCondition() // nothing chosen: left out
        #expect(m.savedRule.conditions.count == 2)
        #expect(FilterEditorModel(rule: FilterRule(matchAll: false)).advanced)
    }

    @Test("a rule reads as a short summary")
    func ruleSummary() {
        #expect(filterRuleSummary(FilterRule(), lists: []) == "所有任务")
        let r = FilterRule(conditions: [FilterCondition(.list, ["work", "gone"]), FilterCondition(.priority, ["high"], exclude: true), FilterCondition(.tag, [])])
        #expect(filterRuleSummary(r, lists: [work]) == "清单：工作、已删除的清单；优先级：不包含 高")
        let any = FilterRule(matchAll: false, conditions: [FilterCondition(.date, ["today"]), FilterCondition(.keyword, ["x"])])
        #expect(filterRuleSummary(any, lists: []) == "日期：今天 或 内容：“x”")
        let unknown = FilterRule.parse(#"{"match":"all","conditions":[{"field":"place","values":["a"]}]}"#)
        #expect(filterRuleSummary(unknown, lists: []) == "新版本加的条件")
    }

    @Test("debug routes for search and the filter editor")
    func routes() {
        for text in ["search", "search:周报", "filter-editor:new", "filter-editor:advanced"] {
            #expect(DebugRoute(text)?.text == text)
        }
        #expect(DebugRoute("search:") == nil)
        #expect(DebugRoute("filter-editor") == nil)
    }
}
