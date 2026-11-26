// iOS search: a page with the system search field (`.searchable`), for the
// search tab or pushed from the task list's magnifying glass. Put it in a
// NavigationStack:
//
//     Tab(role: .search) {
//         NavigationStack {
//             SearchPage(data: …, now: .now(), recentSearches: …,
//                        onOpen: { target in reveal(target) },
//                        onToggleDone: { task, done in … },
//                        onRecentSearchesChange: { queries in … })
//         }
//     }
//
// Tapping a result calls `onOpen`; the caller switches to a view that shows
// it and pushes the task's page (back then goes to that list, not to
// search). Return opens the first result. Text still being composed
// (pinyin not yet turned into characters) isn't searched for.

#if os(iOS)
import OpenTodoDomain
import SwiftUI
import UIKit

public struct SearchPage: View {
    let data: SearchData
    let now: LocalDateTime
    let recentSearches: [String]
    let onOpen: (SearchTarget) -> Void
    let onToggleDone: (TodoTask, Bool) -> Void
    let onRecentSearchesChange: ([String]) -> Void

    @State private var text: String
    /// `text` without what's still being composed.
    @State private var query: String
    @State private var memo = SearchMemo()
    @State private var searching: Bool
    /// The system field last seen changing, to read what's being composed.
    @State private var field = WeakField()

    /// `searchActive` starts with the field focused (as when opened from
    /// the list's magnifying glass).
    public init(
        data: SearchData,
        now: LocalDateTime,
        recentSearches: [String] = [],
        initialQuery: String = "",
        searchActive: Bool = false,
        onOpen: @escaping (SearchTarget) -> Void,
        onToggleDone: @escaping (TodoTask, Bool) -> Void = { _, _ in },
        onRecentSearchesChange: @escaping ([String]) -> Void = { _ in }
    ) {
        self.data = data
        self.now = now
        self.recentSearches = recentSearches
        self.onOpen = onOpen
        self.onToggleDone = onToggleDone
        self.onRecentSearchesChange = onRecentSearchesChange
        _text = State(initialValue: initialQuery)
        _query = State(initialValue: initialQuery)
        _searching = State(initialValue: searchActive)
    }

    public var body: some View {
        let recent = RecentSearches(recentSearches)
        let model = memo.model(query: query, data: data, recent: recent)
        content(model, recent: recent)
            .navigationTitle("搜索")
            .searchable(text: $text, isPresented: $searching, prompt: "任务、清单、标签和过滤器")
            .onSubmit(of: .search) {
                if let first = model.entries.first, model.phase == .results { open(first, model, recent) }
            }
            .onChange(of: text) { _, new in
                query = field.committed(ifShowing: new) ?? new
            }
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { note in
                guard let f = note.object as? UISearchTextField else { return }
                field.field = f
                if let committed = field.committed(ifShowing: f.text ?? "") { query = committed }
            }
    }

    @ViewBuilder
    private func content(_ model: SearchModel, recent: RecentSearches) -> some View {
        if model.entries.isEmpty {
            SearchPlaceholder(model: model)
        } else {
            List {
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            row(entry, model: model, recent: recent)
                        }
                        .onDelete(perform: section.kind == .recent ? { offsets in
                            var r = recent
                            for i in offsets { r = r.removing(section.entries[i].recentQuery ?? "") }
                            onRecentSearchesChange(r.queries)
                        } : nil)
                    } header: {
                        if section.kind == .recent {
                            HStack {
                                Text(section.title)
                                Spacer()
                                Button("清除") { onRecentSearchesChange([]) }
                                    .uiFont(.subheadline)
                                    .textCase(nil)
                            }
                        } else {
                            Text(section.title)
                        }
                    } footer: {
                        if section.kind == .tasks, let note = model.moreTasksNote {
                            Text(note)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func row(_ entry: SearchEntry, model: SearchModel, recent: RecentSearches) -> some View {
        // Not a Button: a task's tick box inside it couldn't be tapped.
        Group {
            switch entry {
            case .recent(let q):
                SearchRecentRow(query: q) {}
            case .task(let hit):
                SearchTaskRow(hit: hit, lists: data.listsById, now: now, onToggleDone: onToggleDone)
            default:
                SearchViewRow(entry: entry, terms: model.terms)
            }
        }
        .contentShape(.rect)
        .onTapGesture { open(entry, model, recent) }
        .accessibilityAddTraits(.isButton)
    }

    private func open(_ entry: SearchEntry, _ model: SearchModel, _ recent: RecentSearches) {
        guard let target = entry.target else {
            if let q = entry.recentQuery {
                text = q
                query = q
                searching = true
            }
            return
        }
        let after = recentAfterOpening(entry, query: model.query, recent: recent)
        if after != recent { onRecentSearchesChange(after.queries) }
        onOpen(target)
    }
}

/// The search field, held weakly: it reports what's being composed.
private final class WeakField {
    weak var field: UITextField?

    /// The field's text without what's being composed, when the field is
    /// showing `text`; nil when it isn't (so the binding's value stands).
    @MainActor
    func committed(ifShowing text: String) -> String? {
        guard let field, field.text == text else { return nil }
        return committedQuery(field)
    }
}

extension SearchEntry {
    var recentQuery: String? {
        if case .recent(let q) = self { q } else { nil }
    }
}
#endif
