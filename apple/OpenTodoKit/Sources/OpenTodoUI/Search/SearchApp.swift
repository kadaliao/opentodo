// Search wired into the app: what it searches (the window's data), what
// choosing a result does, the recent searches kept in `key_values`, and
// where it shows — `SearchHost` puts the panel over the macOS window
// (⌘F, the toolbar's magnifying glass), `SearchScreen` is the iOS 搜索 tab.

import OpenTodoData
import OpenTodoDomain
import SwiftUI

extension AppModel {
    /// Everything search looks through, from the latest snapshot.
    public var searchData: SearchData {
        let d = data
        // The same value for the same snapshot, so search can tell nothing
        // changed (SearchMemo).
        if let cached = derived.searchData { return cached }
        let value = SearchData(tasks: d.tasks, checklist: checklistsByTask, lists: lists, tags: tags, filters: filters)
        derived.searchData = value
        return value
    }

    /// Opens a chosen result: a task where it lives (`revealTask`), a list,
    /// tag or filter as the view. Closes search.
    public func openSearchResult(_ target: SearchTarget) {
        search.isPresented = false
        switch target {
        case .task(let t):
            revealTask(t.id)
        case .view(let v):
            switchTo(.tasks)
            select(v)
        }
    }

    /// Reads the recent searches the first time search opens.
    public func loadRecentSearches() async {
        guard !search.recentLoaded else { return }
        search.recentLoaded = true
        let text = try? await database.getValue(Keys.recentSearches)
        search.recent = RecentSearches(json: text).queries
    }

    public func setRecentSearches(_ queries: [String]) {
        let recent = RecentSearches(queries)
        search.recent = recent.queries
        search.recentLoaded = true
        run { try await self.database.setValue(Keys.recentSearches, recent.isEmpty ? nil : recent.encode()) }
    }
}

/// macOS: the search panel over the whole window while
/// `model.search.isPresented`.
struct SearchHost: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        #if os(macOS)
        @Bindable var search = model.search
        content
            .searchOverlay(isPresented: $search.isPresented) {
                SearchPanel(
                    data: model.searchData, now: model.now, recentSearches: model.search.recent,
                    initialQuery: model.search.prefill,
                    onOpen: { model.openSearchResult($0) },
                    onToggleDone: { task, done in model.run { await model.setDone(task, done) } },
                    onRecentSearchesChange: { model.setRecentSearches($0) },
                    onClose: { model.search.isPresented = false }
                )
                .onDisappear { model.search.prefill = "" }
                .task { await model.loadRecentSearches() }
            }
        #else
        content
        #endif
    }
}

#if os(iOS)
/// iOS: the 搜索 tab.
struct SearchScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            SearchPage(
                data: model.searchData, now: model.now, recentSearches: model.search.recent,
                initialQuery: model.search.prefill, searchActive: !model.search.prefill.isEmpty,
                onOpen: { model.openSearchResult($0) },
                onToggleDone: { task, done in model.run { await model.setDone(task, done) } },
                onRecentSearchesChange: { model.setRecentSearches($0) }
            )
        }
        .task { await model.loadRecentSearches() }
    }
}
#endif
