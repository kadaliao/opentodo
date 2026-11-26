// App Intents: 添加任务 and 打开清单 for Siri and Shortcuts, 完成任务 for the
// widgets' buttons, and the entities they take (a list, a countdown). This
// folder is compiled into the app and the widget extension both (see
// project.yml); the work itself is in `OpenTodoSystem` (`SharedWriter`,
// `WidgetStore`, `AppLink`), which has the tests.

import AppIntents
import Foundation
import OpenTodoSystem
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The widgets show the change straight away.
private func reloadWidgets() {
    #if canImport(WidgetKit)
    WidgetCenter.shared.reloadAllTimelines()
    #endif
}

// MARK: - 完成任务 (widget buttons)

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "完成任务"
    static let description = IntentDescription("把任务标记为完成；重复的任务挪到下一次。")
    /// Only the widgets use it (it takes a task id).
    static let isDiscoverable = false

    @Parameter(title: "任务") var taskId: String

    init() {}

    init(taskId: String) {
        self.taskId = taskId
    }

    func perform() async throws -> some IntentResult {
        try await SharedWriter.open().complete(taskId)
        reloadWidgets()
        return .result()
    }
}

// MARK: - 添加任务

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "添加任务"
    static let description = IntentDescription("在 OpenTodo 里添加一个任务，可以带日期和时间（只给时间就是今天），放进某个清单（不选就是收集箱）。")
    static let openAppWhenRun = false

    @Parameter(title: "标题", requestValueDialog: "要添加什么任务？")
    var title: String

    @Parameter(title: "日期")
    var date: Date?

    /// Only its clock time counts; without a date it is today's.
    @Parameter(title: "时间")
    var time: Date?

    @Parameter(title: "清单")
    var list: ListEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("添加任务“\(\.$title)”") {
            \.$date
            \.$time
            \.$list
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw $title.needsValueError("要添加什么任务？") }
        let due = intentDue(date: date, time: time)
        try await SharedWriter.open().add(title: text, listId: list?.id ?? inboxListId, date: due.day, time: due.minute)
        reloadWidgets()
        return .result(dialog: "已添加“\(text)”")
    }
}

// MARK: - 打开清单

struct OpenListIntent: AppIntent {
    static let title: LocalizedStringResource = "打开清单"
    static let description = IntentDescription("在 OpenTodo 里打开一个清单。")

    @Parameter(title: "清单")
    var list: ListEntity

    static var parameterSummary: some ParameterSummary {
        Summary("打开\(\.$list)")
    }

    init() {}

    init(list: ListEntity) {
        self.list = list
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppLink.list(list.id).url()))
    }
}

// MARK: - Entities

/// A list (清单), 收集箱 included.
struct ListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "清单"
    static let defaultQuery = ListQuery()

    let id: String
    let name: String
    let emoji: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji.map { "\($0) " } ?? "")\(name)")
    }

    static let inbox = ListEntity(id: inboxListId, name: "收集箱", emoji: nil)
}

struct ListQuery: EntityStringQuery {
    init() {}

    private func all() async -> [ListEntity] {
        let lists = await WidgetStore.taskData(WidgetStore.open()).lists.filter { $0.id != inboxListId }
        return [ListEntity.inbox] + lists.map { ListEntity(id: $0.id, name: $0.name, emoji: $0.emoji) }
    }

    func entities(for identifiers: [String]) async throws -> [ListEntity] {
        await all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ListEntity] {
        await all().filter { $0.name.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [ListEntity] {
        await all()
    }
}

/// A countdown (倒数日), for the countdown widget's choice.
struct CountdownEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "倒数日"
    static let defaultQuery = CountdownQuery()

    let id: String
    let title: String
    let emoji: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji.map { "\($0) " } ?? "")\(title)")
    }
}

struct CountdownQuery: EntityQuery {
    init() {}

    private func all() async -> [CountdownEntity] {
        let today = Day.today()
        return sortCountdowns(await WidgetStore.countdowns(WidgetStore.open()), today: today)
            .map { CountdownEntity(id: $0.id, title: $0.title, emoji: $0.emoji) }
    }

    func entities(for identifiers: [String]) async throws -> [CountdownEntity] {
        await all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CountdownEntity] {
        await all()
    }
}

/// The countdown widget's setting: which one it shows (none picked: the
/// first of the countdowns page).
struct SelectCountdownIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择倒数日"
    static let description = IntentDescription("小组件显示哪个倒数日。")

    @Parameter(title: "倒数日")
    var countdown: CountdownEntity?

    init() {}
}
