// Search and filters wired into AppModel, over a real (in-memory) database:
// the flows of `app/test/search_filter_ui_test.dart` as the app runs them
// (the editor's and the panel's own steps are in SearchFilterUITests).

import Foundation
#if os(macOS)
import AppKit
#endif
import OpenTodoData
import OpenTodoDomain
import Testing
@testable import OpenTodoUI

nonisolated private let tz = TimeZone(identifier: "Asia/Shanghai")!
nonisolated private let now = LocalDateTime(2026, 11, 26, 9, 41)

private func waitUntil(_ what: String = "", _ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("timed out \(what)")
}

private func settle(_ model: AppModel) async throws {
    let data = try await model.database.observeTaskData().first()
    try await waitUntil { model.data == data }
}

/// Two lists and a few tasks: 写周报 (工作, high), 整理桌面 (工作), 交房租
/// (家里, high), 读书 (收集箱), and 开会 whose subtask mentions 周报.
private struct Fixture {
    let model: AppModel
    let work: String
    let home: String
    let meeting: String
}

private func makeFixture() async throws -> Fixture {
    let db = try AppDatabase.inMemory()
    let settings = LocalSettings(db)
    let repo = TaskRepo(db, clock: { now.date(in: tz) }, defaults: settings.defaultsProvider, timeZone: tz)
    let work = try await repo.addList("工作", emoji: "💼")
    let home = try await repo.addList("家里", emoji: "🏠")
    try await repo.addTask(title: "写周报", listId: work, priority: .high)
    try await repo.addTask(title: "整理桌面", listId: work)
    try await repo.addTask(title: "交房租", listId: home, priority: .high)
    try await repo.addTask(title: "读书")
    let meeting = try await repo.addTask(title: "开会", listId: home)
    try await repo.addChecklistItem(meeting, "带上周报模板")
    let model = AppModel(repo: repo, settings: settings, now: now)
    await model.start(clock: false)
    try await waitUntil { model.loaded }
    try await settle(model)
    return Fixture(model: model, work: work, home: home, meeting: meeting)
}

private func titles(_ m: AppModel, _ view: ViewRef) -> [String] {
    m.sections(for: view).flatMap(\.tasks).map(\.title)
}

@Suite struct SearchFilterAppTests {
    @Test func desktopMakeAFilterAddToItChangeItDeleteIt() async throws {
        let f = try await makeFixture()
        let m = f.model
        #expect(m.filters.isEmpty) // the sidebar's hint shows

        // 添加过滤器 → 工作, 高 → 保存.
        m.editFilter()
        let request = try #require(m.present.filterEditor)
        #expect(request.filter == nil)
        var editor = FilterEditorModel(filter: request.filter)
        #expect(editor.matchingCount(m.data.tasks, now: m.now) == 5)
        editor.name = "重要工作"
        editor.setSimpleValues(.list, [f.work])
        editor.setPriority("high", on: true)
        #expect(editor.matchingCount(m.data.tasks, now: m.now) == 1)
        await m.saveFilter(request, try #require(editor.result()))
        try await settle(m)

        let filter = try #require(m.filters.first)
        #expect(filter.name == "重要工作")
        #expect(m.view == .filter(filter.id))
        #expect(m.title(of: m.view) == "重要工作")
        #expect(titles(m, m.view) == ["写周报"])

        // A task added here gets the filter's list and priority.
        let added = try #require(await m.quickAdd("准备材料"))
        try await settle(m)
        let t = try #require(m.task(added))
        #expect(t.listId == f.work && t.priority == .high)
        #expect(titles(m, m.view).contains("准备材料"))

        // In 高级, turn the priority around: 工作 tasks that are not high.
        m.editFilter(filter)
        let edit = try #require(m.present.filterEditor)
        var e = FilterEditorModel(filter: edit.filter)
        e.setAdvanced(true)
        e.setExclude(at: 1, true)
        #expect(!e.canSimple)
        await m.saveFilter(edit, try #require(e.result()))
        try await settle(m)
        #expect(m.filters.count == 1)
        #expect(titles(m, m.view) == ["整理桌面"])

        // Delete it from the sidebar's menu: asks first, then back to 今天.
        m.askDeleteFilter(filter)
        let confirm = try #require(m.present.confirm)
        #expect(confirm.title == "删除过滤器“重要工作”？")
        confirm.onConfirm()
        try await waitUntil { m.filters.isEmpty }
        #expect(m.view == .smart(.today))
    }

    @Test func aFilterDeletedElsewhereWhileOnScreenGoesBackToToday() async throws {
        let f = try await makeFixture()
        let m = f.model
        let id = try await m.repo.addFilter("远程", "{}")
        try await settle(m)
        m.select(.filter(id))
        #expect(m.title(of: m.view) == "远程")
        try await m.repo.deleteFilter(id) // as a sync would
        try await waitUntil { m.view == .smart(.today) }
    }

    @Test func filtersAreDraggedIntoOrder() async throws {
        let f = try await makeFixture()
        let m = f.model
        let a = try await m.repo.addFilter("甲", "{}")
        let b = try await m.repo.addFilter("乙", "{}")
        let c = try await m.repo.addFilter("丙", "{}")
        try await settle(m)
        #expect(m.filters.map(\.id) == [a, b, c])
        await m.moveFilter(c, to: 0)
        try await settle(m)
        #expect(m.filters.map(\.id) == [c, a, b])
        await m.moveFilter(c, to: 3)
        try await settle(m)
        #expect(m.filters.map(\.id) == [a, b, c])
        #expect(m.filters.allSatisfy { $0.dirty }) // to be synced
    }

    @Test func desktopCommandFSearchesArrowsAndReturnOpenATask() async throws {
        let f = try await makeFixture()
        let m = f.model
        m.requestSearch() // ⌘F
        #expect(m.search.isPresented)

        let results = SearchModel(query: "周报", data: m.searchData)
        #expect(results.entries.map { if case .task(let h) = $0 { h.task.title } else { "" } } == ["写周报", "开会"])
        guard case .task(let hit) = results.entries[1] else { Issue.record(); return }
        #expect(hit.snippet == "☐ 带上周报模板") // found in a subtask
        var cursor = SearchCursor()
        cursor.move(1, in: results)              // ↓, then Return
        m.openSearchResult(results.entries[cursor.active(in: results)!].target!)
        #expect(!m.search.isPresented)
        #expect(m.selectedTaskId == f.meeting)
        #expect(m.view == .list(f.home))

        // A list opens as a view.
        m.requestSearch()
        let lists = SearchModel(query: "工作", data: m.searchData)
        #expect(lists.sections.first?.title == "清单")
        m.openSearchResult(lists.entries[0].target!)
        #expect(m.view == .list(f.work))
        #expect(m.selectedTaskId == nil)

        // Nothing found.
        #expect(SearchModel(query: "火星", data: m.searchData).phase == .noResults)
    }

    @Test func phoneSearchIsAPageATaskOpensAsItsOwnPage() async throws {
        let f = try await makeFixture()
        let m = f.model
        m.setWidth(.compact)
        m.search.isPresented = true // the 搜索 tab
        let results = SearchModel(query: "房租", data: m.searchData)
        guard case .task(let t)? = results.entries.first?.target else { Issue.record(); return }
        m.openSearchResult(.task(t))
        #expect(!m.search.isPresented) // back on the tasks tab
        #expect(m.phonePath == [.view(.list(f.home)), .task(t.id)])
        // Back goes to the list, not to search.
        m.phonePath.removeLast()
        m.phonePathChanged()
        #expect(m.view == .list(f.home))
        #expect(!m.search.isPresented)
    }

    @Test func recentSearchesAreKeptInKeyValues() async throws {
        let f = try await makeFixture()
        let m = f.model
        await m.loadRecentSearches()
        #expect(m.search.recent.isEmpty)
        let recent = recentAfterOpening(.list(TaskList(id: "x")), query: "周报 ", recent: RecentSearches(m.search.recent))
        m.setRecentSearches(recent.queries)
        #expect(m.search.recent == ["周报"])
        try await waitUntil { (try? m.database.getValueNow(Keys.recentSearches)) == #"["周报"]"# }
        // Another window reads them back.
        let other = AppModel(repo: m.repo, settings: m.settings, now: now)
        await other.loadRecentSearches()
        #expect(other.search.recent == ["周报"])
        // Clearing removes the key.
        m.setRecentSearches([])
        try await waitUntil { (try? m.database.getValueNow(Keys.recentSearches)) == .some(nil) }
    }
}

// MARK: - Text still being composed

private struct FakeField: ComposingInput {
    var fullText: String
    var markedUTF16Range: NSRange?
}

@Suite struct ComposingTests {
    @Test func theQueryLeavesOutWhatIsBeingComposed() {
        #expect(committedQuery(FakeField(fullText: "周报zhou", markedUTF16Range: NSRange(location: 2, length: 4))) == "周报")
        #expect(committedQuery(FakeField(fullText: "周报", markedUTF16Range: nil)) == "周报")
        #expect(committedQuery(FakeField(fullText: "a zh b", markedUTF16Range: NSRange(location: 2, length: 2))) == "a  b")
    }

    #if os(macOS)
    /// The panel's field reads the query from its field editor, an
    /// NSTextView: marked text set the way an input method sets it is left
    /// out until it's committed.
    @Test func anAppKitTextViewReportsItsMarkedText() {
        let tv = NSTextView()
        tv.insertText("周报", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(committedQuery(tv) == "周报")
        tv.setMarkedText("zhou", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(tv.string == "周报zhou")
        #expect(committedQuery(tv) == "周报")
        // The input method turns it into a character.
        tv.insertText("周", replacementRange: tv.markedRange())
        #expect(tv.string == "周报周")
        #expect(committedQuery(tv) == "周报周")
    }
    #endif
}
