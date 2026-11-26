// What the search panel shows and how the keyboard moves through it, kept
// apart from the views so it can be tested (the Dart version's
// `_SearchPanelState`, `app/lib/ui/search_panel.dart`).
//
// The panel takes everything as values (`SearchData`, `now`, the recent
// searches) and reports what the person did through callbacks; it never
// touches the database. See `SearchPanel` (macOS) and `SearchPage` (iOS).

import Foundation
import OpenTodoDomain
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Everything search looks through: the tasks not yet in the trash are
/// picked out by `search` itself, so pass them all.
public struct SearchData: Sendable, Hashable {
    public var tasks: [TodoTask]
    /// Subtasks by task id.
    public var checklist: [String: [ChecklistItem]]
    public var lists: [TaskList]
    public var tags: [String]
    public var filters: [TaskFilter]

    public init(
        tasks: [TodoTask] = [],
        checklist: [String: [ChecklistItem]] = [:],
        lists: [TaskList] = [],
        tags: [String] = [],
        filters: [TaskFilter] = []
    ) {
        self.tasks = tasks
        self.checklist = checklist
        self.lists = lists
        self.tags = tags
        self.filters = filters
    }

    var listsById: [String: TaskList] {
        Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

/// What a chosen result opens. A task goes through the caller's
/// `revealTask` (switch to a view that lists it — `viewForTask` — select
/// it, and on a phone open its page); a view is selected as it is.
public enum SearchTarget: Sendable, Hashable {
    case task(TodoTask)
    case view(ViewRef)
}

/// One row the arrow keys move through.
public enum SearchEntry: Sendable, Hashable, Identifiable {
    /// A recent search, shown before anything is typed; choosing it types it.
    case recent(String)
    case list(TaskList)
    case filter(TaskFilter)
    case tag(String)
    case task(TaskHit)

    public var id: String {
        switch self {
        case .recent(let q): "recent:\(q)"
        case .list(let l): "list:\(l.id)"
        case .filter(let f): "filter:\(f.id)"
        case .tag(let t): "tag:\(t)"
        case .task(let h): "task:\(h.task.id)"
        }
    }

    /// What it opens; nil for a recent search.
    public var target: SearchTarget? {
        switch self {
        case .recent: nil
        case .list(let l): .view(.list(l.id))
        case .filter(let f): .view(.filter(f.id))
        case .tag(let t): .view(.tag(t))
        case .task(let h): .task(h.task)
        }
    }
}

public struct SearchSection: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable { case recent, lists, filters, tags, tasks }

    public var kind: Kind
    public var entries: [SearchEntry]
    /// Where its first entry is in `SearchModel.entries`.
    public var start: Int

    public var id: Kind { kind }

    public var title: String {
        switch kind {
        case .recent: "最近搜索"
        case .lists: "清单"
        case .filters: "过滤器"
        case .tags: "标签"
        case .tasks: "任务"
        }
    }
}

/// The results for one query, laid out as the panel shows them.
public struct SearchModel: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        /// Nothing typed: the prompt, and the recent searches if any.
        case start
        case noResults
        case results
    }

    public let query: String
    public let terms: [String]
    public let results: SearchResults
    public let sections: [SearchSection]
    /// Every row in order: recent searches, or lists, filters, tags, tasks.
    public let entries: [SearchEntry]

    /// `query` is what's in the field without text still being composed
    /// (`committedText`).
    public init(query: String, data: SearchData, recent: RecentSearches = RecentSearches()) {
        self.query = query
        terms = searchTerms(query)
        results = search(
            query,
            tasks: data.tasks,
            checklist: data.checklist,
            lists: data.lists,
            tags: data.tags,
            filters: data.filters
        )
        var sections: [SearchSection] = []
        var start = 0
        func add(_ kind: SearchSection.Kind, _ entries: [SearchEntry]) {
            guard !entries.isEmpty else { return }
            sections.append(SearchSection(kind: kind, entries: entries, start: start))
            start += entries.count
        }
        if terms.isEmpty {
            add(.recent, recent.queries.map(SearchEntry.recent))
        } else {
            add(.lists, results.lists.map(SearchEntry.list))
            add(.filters, results.filters.map(SearchEntry.filter))
            add(.tags, results.tags.map(SearchEntry.tag))
            add(.tasks, results.tasks.map(SearchEntry.task))
        }
        self.sections = sections
        entries = sections.flatMap(\.entries)
    }

    public var phase: Phase {
        if terms.isEmpty { return .start }
        return entries.isEmpty ? .noResults : .results
    }

    /// The query as the empty state quotes it: 没有找到“火星”.
    public var noResultsTitle: String { "没有找到“\(query.trimmingCharacters(in: .whitespaces))”" }

    /// 还有 N 个任务，多输几个字缩小范围, when more tasks were found than listed.
    public var moreTasksNote: String? {
        results.moreTasks > 0 ? "还有 \(results.moreTasks) 个任务，多输几个字缩小范围" : nil
    }
}

/// The highlighted row. Typing puts it back on the first result; before
/// anything is typed no recent search is highlighted until an arrow key is
/// pressed.
public struct SearchCursor: Sendable, Hashable {
    /// Nil: the default (the first result; nothing among recent searches).
    public private(set) var index: Int?

    public init(index: Int? = nil) {
        self.index = index
    }

    /// The highlighted row of `model`, if any.
    public func active(in model: SearchModel) -> Int? {
        let count = model.entries.count
        guard count > 0 else { return nil }
        if let index { return min(max(index, 0), count - 1) }
        return model.phase == .results ? 0 : nil
    }

    /// One row down (`delta` 1) or up (-1), stopping at either end.
    public mutating func move(_ delta: Int, in model: SearchModel) {
        let count = model.entries.count
        guard count > 0 else { return }
        let from = active(in: model) ?? -1
        index = min(max(from + delta, 0), count - 1)
    }

    /// Back to the default, as when the query changes.
    public mutating func reset() {
        index = nil
    }
}

/// What the field holds once the text still being composed (pinyin typed
/// but not yet turned into characters) is left out: the parts before and
/// after it. `marked` is a UTF-16 range (`NSRange` location and length), as
/// the text input systems report it.
public func committedText(_ text: String, marked: NSRange?) -> String {
    guard let marked, marked.location != NSNotFound, marked.length > 0 else { return text }
    let ns = text as NSString
    guard marked.location + marked.length <= ns.length else { return text }
    return ns.substring(to: marked.location) + ns.substring(from: marked.location + marked.length)
}

/// A text input that may hold text still being composed: what the search
/// fields read the query from. AppKit's `NSTextView` (the field editor of
/// the panel's field) and UIKit's `UITextField` (the system search field)
/// conform below; tests use their own.
protocol ComposingInput {
    /// Everything in the field, composed part included.
    var fullText: String { get }
    /// The part still being composed (UTF-16), or nil.
    var markedUTF16Range: NSRange? { get }
}

/// What to search for in `input`: its text without the part still being
/// composed.
func committedQuery(_ input: some ComposingInput) -> String {
    committedText(input.fullText, marked: input.markedUTF16Range)
}

#if os(macOS)
extension NSTextView: ComposingInput {
    var fullText: String { string }
    var markedUTF16Range: NSRange? { hasMarkedText() ? markedRange() : nil }
}
#endif

#if os(iOS)
extension UITextField: ComposingInput {
    var fullText: String { text ?? "" }
    var markedUTF16Range: NSRange? {
        guard let marked = markedTextRange else { return nil }
        let start = offset(from: beginningOfDocument, to: marked.start)
        return NSRange(location: start, length: offset(from: marked.start, to: marked.end))
    }
}
#endif

/// The recent searches after `entry` was opened for `query`: the query
/// goes to the top. Choosing a recent search doesn't count until something
/// is opened with it.
public func recentAfterOpening(_ entry: SearchEntry, query: String, recent: RecentSearches) -> RecentSearches {
    if case .recent = entry { return recent }
    return recent.adding(query)
}
