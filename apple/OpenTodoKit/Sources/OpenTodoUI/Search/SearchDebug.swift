// Debug routes for search and the filter editor; the filter editor's on
// demo data of its own:
//
//     search                 the app's search panel (macOS) / tab (iOS) on the
//                            launch's data (-OTSeed demo), nothing typed
//     search:<query>         with <query> typed, e.g. search:汇报, search:zb,
//                            search:火星 (nothing found)
//     filter-editor:new      adding a filter
//     filter-editor:simple   editing one in 普通
//     filter-editor:advanced 高级 with 不包含 and 任一 (普通 greyed out)
//     filter-editor:legacy   a deleted list and a condition from a newer version
//     filter-editor:range    a custom date range
//     filter-editor:delete   asking before deleting one
//     filter-editor:picker   the date choices with a custom range
//     filter-editor:rule     the rule editor on its own (FilterRuleRow and
//                            FilterRuleEditor in a form of another feature)

import OpenTodoDomain
import SwiftUI

enum SearchDemo {
    static let work = TaskList(id: "demo-work", name: "工作", emoji: "💼", sortOrder: 1, dirty: false)
    static let home = TaskList(id: "demo-home", name: "家里", emoji: "🏠", sortOrder: 2, dirty: false)
    static let reading = TaskList(id: "demo-reading", name: "读书笔记", emoji: "📚", sortOrder: 3, dirty: false)
    static let gone = TaskList(id: "demo-gone", name: "旧项目", sortOrder: 4, deletedAt: 1, dirty: false)
    static var lists: [TaskList] { [work, home, reading] }
    static let tags = ["周报", "会议", "购物"]

    static func data(today: Day) -> SearchData {
        var n = 0
        func t(
            _ title: String, list: TaskList? = nil, priority: Priority = .none, due: Int? = nil, time: Int? = nil,
            content: String = "", tags: [String] = [], done: Bool = false
        ) -> TodoTask {
            n += 1
            return TodoTask(
                id: "demo-\(n)", listId: list?.id ?? inboxListId, title: title, content: content, priority: priority,
                dueDate: due.map { today + $0 }, dueTime: time, tags: tags, status: done ? .done : .open,
                sortOrder: Double(n), createdAt: n, updatedAt: 1000 - n, dirty: false
            )
        }
        let tasks = [
            t("写周报", list: work, priority: .high, due: 0, time: 17 * 60, tags: ["周报"]),
            t("整理桌面", list: work),
            t("交房租", list: home, priority: .high, due: -2),
            t("读书", content: "《置身事内》第三章"),
            t("开会", list: home, priority: .medium, due: 1),
            t("季度总结", list: work, priority: .low, due: 5, content: "下周一前把本季度的周报汇总，附上主要指标和下季度计划。"),
            t("买菜", list: home, tags: ["购物"]),
            t("上周周报", list: work, due: -5, done: true),
            t("和设计组对一下 Q4 排期", list: work, due: 3, tags: ["会议"]),
        ]
        let meeting = tasks[4].id
        return SearchData(
            tasks: tasks,
            checklist: [meeting: [
                ChecklistItem(id: "demo-c1", taskId: meeting, title: "带上周报模板", dirty: false),
                ChecklistItem(id: "demo-c2", taskId: meeting, title: "订会议室", done: true, dirty: false),
            ]],
            lists: lists,
            tags: tags,
            filters: filters
        )
    }

    static let recent = ["房租", "zb", "季度"]

    static let filters = [
        TaskFilter(id: "demo-f1", name: "本周要交的周报", rule: FilterRule(conditions: [
            FilterCondition(.list, [work.id]), FilterCondition(.date, ["thisWeek"]), FilterCondition(.priority, ["high", "medium"]),
            FilterCondition(.keyword, ["周报"]),
        ]).encode(), dirty: false),
        TaskFilter(id: "demo-f2", name: "家里不急的事", rule: FilterRule(matchAll: false, conditions: [
            FilterCondition(.list, [home.id, inboxListId]), FilterCondition(.priority, ["high"], exclude: true),
            FilterCondition(.tag, ["", "购物"]),
        ]).encode(), dirty: false),
        TaskFilter(id: "demo-f3", name: "旧项目和新条件", rule: #"{"match":"all","conditions":[{"field":"list","values":["demo-gone","demo-work"]},{"field":"tag","values":["周报"]},{"field":"place","values":["office"]}]}"#, dirty: false),
    ]

    static func rangeFilter(today: Day) -> TaskFilter {
        TaskFilter(id: "demo-f4", name: "出差那几天", rule: FilterRule(conditions: [
            FilterCondition(.date, ["overdue", FilterDateRange(today + 3, today + 9).value]),
            FilterCondition(.list, [work.id]),
        ]).encode(), dirty: false)
    }
}

/// Opens the debug screens above over the app's window.
struct SearchDebugScreens: ViewModifier {
    let route: DebugRoute?

    func body(content: Content) -> some View {
        switch route {
        case .search(let q)?:
            content.modifier(SearchDemoHost(initialQuery: q ?? ""))
        case .filterEditor(let state)?:
            content.modifier(FilterEditorDemoHost(state: state))
        default:
            content
        }
    }
}

/// Opens the app's own search (on whatever data the launch gave it, e.g.
/// `-OTSeed demo`) with `initialQuery` typed in.
private struct SearchDemoHost: ViewModifier {
    let initialQuery: String
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.task {
            model.search.prefill = initialQuery
            model.search.isPresented = true
        }
    }
}

private struct FilterEditorDemoHost: ViewModifier {
    let state: String
    @State private var shown = true
    @State private var deleting: TaskFilter?

    func body(content: Content) -> some View {
        let today = Day.today()
        let data = SearchDemo.data(today: today)
        let filter: TaskFilter? = switch state {
        case "simple": data.filters[0]
        case "advanced": data.filters[1]
        case "legacy": data.filters[2]
        case "range": SearchDemo.rangeFilter(today: today)
        default: nil
        }
        if state == "rule" {
            content.sheet(isPresented: $shown) { RuleEditorDemo(today: today) }
        } else if state == "picker" {
            content.sheet(isPresented: $shown) { DatePickerDemo(today: today) }
        } else if state == "delete" {
            content
                .onAppear { deleting = data.filters[0] }
                .filterDeleteConfirmation($deleting) { print("delete \($0.id)") }
        } else {
            content.sheet(isPresented: $shown) {
                FilterEditor(
                    filter: filter, lists: SearchDemo.lists + [SearchDemo.gone], tags: SearchDemo.tags,
                    tasks: data.tasks, now: .now(),
                    onSave: { print("save \($0.name) \($0.rule.encode())") }
                )
            }
        }
    }
}

private struct DatePickerDemo: View {
    let today: Day
    @State private var values: [String] = []

    var body: some View {
        let context = FilterPickerContext(lists: SearchDemo.lists, tags: SearchDemo.tags, today: today)
        NavigationStack {
            FilterValueChecklist(field: .date, values: $values, context: context)
                .navigationTitle("日期：\(context.summary(.date, values))")
                #if os(macOS)
                .frame(width: 280, height: 420)
                #endif
        }
        .onAppear { values = ["today", FilterDateRange(today + 3, today + 9).value] }
    }
}

private struct RuleEditorDemo: View {
    let today: Day
    @State private var quadrant = FilterRule(conditions: [FilterCondition(.priority, ["high"]), FilterCondition(.date, ["today", "overdue"])])
    @State private var calendar = FilterRule(conditions: [FilterCondition(.list, [SearchDemo.work.id])])

    var body: some View {
        NavigationStack {
            Form {
                Section("象限1") {
                    LabeledContent("名称", value: "重要且紧急")
                    FilterRuleRow(rule: $quadrant, lists: SearchDemo.lists, tags: SearchDemo.tags, today: today)
                }
                FilterRuleEditor(rule: $calendar, lists: SearchDemo.lists, tags: SearchDemo.tags, today: today,
                                 footer: calendar.encode())
            }
            .formStyle(.grouped)
            .navigationTitle("别的功能里的规则")
            #if os(macOS)
            .frame(width: 540, height: 560)
            #endif
        }
    }
}
