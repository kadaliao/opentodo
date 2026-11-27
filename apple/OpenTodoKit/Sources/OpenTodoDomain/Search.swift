// Search across tasks (titles, notes, subtasks, tags), lists, tags and
// saved filters, ported from `app/lib/domain/search.dart`.
//
// The query is split on spaces; everything found must contain every word,
// ignoring case. A leading `#` is dropped, so `#工作` finds the tag 工作.
// Titles and names can also be typed in pinyin: `zhoubao` or `zb` finds 周报
// (two letters at least, so one letter doesn't find half the list). The
// Swift version also looks for pinyin in the notes (the Dart version only
// in titles and names); subtasks and tags only as typed.
//
// Ranges to highlight are UTF-16 offsets `start..<end`, as in Dart; turn one
// into a `String.Index` range with `String.Index(utf16Offset:in:)`.

/// UTF-16 ranges to highlight.
public typealias TextRanges = [Range<Int>]

public func searchTerms(_ query: String) -> [String] {
    query.split(whereSeparator: { $0.unicodeScalars.allSatisfy(\.properties.isWhitespace) }).compactMap { w in
        let word = w.drop { $0 == "#" }
        return word.isEmpty ? nil : String(word).lowercased()
    }
}

/// Where `term` is spelled in pinyin in `text` (see `pinyinRanges`); only
/// for two letters or more.
private func pinyin(_ text: String, _ term: String) -> TextRanges {
    term.utf16.count < 2 ? [] : pinyinRanges(text, term)
}

/// Whether `text` has `term` as it is or in pinyin.
private func has(_ text: String, _ lower: String, _ term: String) -> Bool {
    utf16Contains(lower, term) || !pinyin(text, term).isEmpty
}

/// Where `terms` occur in `text` (as typed, or in pinyin when `pinyin`),
/// sorted and merged.
public func findRanges(_ text: String, _ terms: [String], pinyin usePinyin: Bool = true) -> TextRanges {
    let lower = Array(text.lowercased().utf16)
    // Lowercasing can change the length of a few scripts; positions would
    // then be off, so don't highlight rather than highlight the wrong part.
    guard lower.count == text.utf16.count else { return [] }
    var found: TextRanges = []
    for term in terms {
        let t = Array(term.utf16)
        var i = utf16Index(of: t, in: lower)
        while i >= 0 {
            found.append(i..<i + t.count)
            i = utf16Index(of: t, in: lower, from: i + t.count)
        }
        if usePinyin { found += pinyin(text, term) }
    }
    found.sort { $0.lowerBound < $1.lowerBound }
    var merged: TextRanges = []
    for r in found {
        if let last = merged.last, r.lowerBound <= last.upperBound {
            merged[merged.count - 1] = last.lowerBound..<max(r.upperBound, last.upperBound)
        } else {
            merged.append(r)
        }
    }
    return merged
}

private func hasAll(_ text: String, _ terms: [String]) -> Bool {
    let lower = text.lowercased()
    return terms.allSatisfy { has(text, lower, $0) }
}

/// The tags to offer while one is being typed (添加标签): all of `tags`
/// when nothing is typed; else those search would find (ignoring case and
/// a leading `#`, Chinese also in pinyin: `gz` for 工作), the ones that
/// start with it first, each group in the order given.
public func tagSuggestions(_ tags: [String], typed: String) -> [String] {
    let terms = searchTerms(typed)
    guard !terms.isEmpty else { return tags }
    var starting: [String] = []
    var containing: [String] = []
    for tag in tags {
        let ranges = terms.map { findRanges(tag, [$0]) }
        guard ranges.allSatisfy({ !$0.isEmpty }) else { continue }
        if ranges[0].first?.lowerBound == 0 { starting.append(tag) } else { containing.append(tag) }
    }
    return starting + containing
}

public struct TaskHit: Sendable, Hashable {
    public var task: TodoTask
    public var titleRanges: TextRanges
    /// A line from the notes, a subtask or the tags, when the title alone
    /// doesn't show why the task was found.
    public var snippet: String?
    public var snippetRanges: TextRanges

    public init(task: TodoTask, titleRanges: TextRanges, snippet: String? = nil, snippetRanges: TextRanges = []) {
        self.task = task
        self.titleRanges = titleRanges
        self.snippet = snippet
        self.snippetRanges = snippetRanges
    }
}

public struct SearchResults: Sendable, Hashable {
    public var tasks: [TaskHit]
    public var lists: [TaskList]
    public var tags: [String]
    public var filters: [TaskFilter]
    /// Tasks found beyond the ones listed.
    public var moreTasks: Int

    public init(tasks: [TaskHit] = [], lists: [TaskList] = [], tags: [String] = [], filters: [TaskFilter] = [], moreTasks: Int = 0) {
        self.tasks = tasks
        self.lists = lists
        self.tags = tags
        self.filters = filters
        self.moreTasks = moreTasks
    }

    public var isEmpty: Bool { tasks.isEmpty && lists.isEmpty && tags.isEmpty && filters.isEmpty }
}

/// Finds `query` in everything; tasks in the trash are left out. Open tasks
/// come before finished ones, and within those, title matches first, then
/// the most recently changed.
public func search(
    _ query: String,
    tasks: [TodoTask],
    checklist: [String: [ChecklistItem]] = [:],
    lists: [TaskList] = [],
    tags: [String] = [],
    filters: [TaskFilter] = [],
    taskLimit: Int = 100
) -> SearchResults {
    let terms = searchTerms(query)
    if terms.isEmpty { return SearchResults() }

    var hits: [(hit: TaskHit, score: Int)] = []
    for t in tasks where t.trashedAt == nil {
        let items = checklist[t.id] ?? []
        let title = t.title.lowercased()
        let content = t.content.lowercased()
        let inTitle = terms.map { has(t.title, title, $0) }
        let notesHan = hasHan(t.content)
        let found = terms.indices.allSatisfy { k in
            let w = terms[k]
            return inTitle[k]
                || utf16Contains(content, w)
                || (notesHan && !pinyin(t.content, w).isEmpty)
                || items.contains { utf16Contains($0.title.lowercased(), w) }
                || t.tags.contains { utf16Contains($0.lowercased(), w) }
        }
        if !found { continue }
        let titleHasAll = !inTitle.contains(false)
        let snippet = titleHasAll ? nil : makeSnippet(t, items, terms.indices.filter { !inTitle[$0] }.map { terms[$0] })
        hits.append((
            hit: TaskHit(
                task: t,
                titleRanges: findRanges(t.title, terms),
                snippet: snippet?.text,
                snippetRanges: snippet.map { findRanges($0.text, terms, pinyin: $0.fromNotes) } ?? []
            ),
            score: titleHasAll ? 2 : (inTitle.contains(true) ? 1 : 0)
        ))
    }
    hits.sort(comparing: { a, b in
        let ao = a.hit.task.status == .open, bo = b.hit.task.status == .open
        if ao != bo { return ao ? -1 : 1 }
        if a.score != b.score { return compareValues(b.score, a.score) }
        return compareValues(b.hit.task.updatedAt, a.hit.task.updatedAt)
    })
    let shown = hits.prefix(max(taskLimit, 0)).map(\.hit)

    return SearchResults(
        tasks: shown,
        lists: lists.filter { hasAll($0.name, terms) },
        tags: tags.filter { hasAll($0, terms) },
        filters: filters.filter { hasAll($0.name, terms) },
        moreTasks: hits.count - shown.count
    )
}

/// The part of the notes around the first of the words the title lacks
/// (`missing`), as typed or in pinyin; else the subtask that has it; else
/// the tags. `fromNotes` says it's from the notes (highlighted with pinyin).
private func makeSnippet(_ t: TodoTask, _ items: [ChecklistItem], _ missing: [String]) -> (text: String, fromNotes: Bool)? {
    let content = collapsingWhitespace(t.content).dartTrimmed
    let units = Array(content.utf16)
    let lower = Array(content.lowercased().utf16)
    if lower.count == units.count {
        var at = missing.map { utf16Index(of: Array($0.utf16), in: lower) }.filter { $0 >= 0 }
        if at.isEmpty && hasHan(content) {
            at = missing.compactMap { pinyin(content, $0).first?.lowerBound }
        }
        if let first = at.min() {
            let before = 12, after = 60
            let start = first > before ? first - before : 0
            let end = min(first + after, units.count)
            let middle = String(decoding: units[start..<end], as: UTF16.self)
            return ((start > 0 ? "…" : "") + middle + (end < units.count ? "…" : ""), true)
        }
    }
    for i in items {
        let lower = i.title.lowercased()
        if missing.contains(where: { utf16Contains(lower, $0) }) { return ("\(i.done ? "☑" : "☐") \(i.title)", false) }
    }
    let tags = t.tags.filter { tag in missing.contains { utf16Contains(tag.lowercased(), $0) } }
    if !tags.isEmpty { return (tags.map { "#\($0)" }.joined(separator: " "), false) }
    return nil
}

/// Each run of whitespace as one space (Dart's `replaceAll(RegExp(r'\s+'), ' ')`).
private func collapsingWhitespace(_ s: String) -> String {
    var out = String.UnicodeScalarView()
    var inSpace = false
    for u in s.unicodeScalars {
        if u.properties.isWhitespace {
            if !inSpace { out.append(" ") }
            inSpace = true
        } else {
            out.append(u)
            inSpace = false
        }
    }
    return String(out)
}

// MARK: - Recent searches (Swift version only)

/// What was searched for lately, newest first, shown before anything is
/// typed. Kept on this device only, in `key_values` under `search.recent`
/// (`Keys.recentSearches`) as a JSON array of strings. Unreadable contents
/// read as none.
public struct RecentSearches: Sendable, Hashable {
    /// How many are kept.
    public static let limit = 10

    public private(set) var queries: [String]

    public init(_ queries: [String] = []) {
        var out: [String] = []
        for q in queries.map(Self.normalized) where !q.isEmpty && !out.contains(where: { Self.same($0, q) }) {
            out.append(q)
        }
        self.queries = Array(out.prefix(Self.limit))
    }

    /// Reads the stored text.
    public init(json text: String?) {
        let values = text.flatMap { JSONValue(parsing: $0)?.array } ?? []
        self.init(values.compactMap(\.string))
    }

    /// The text to store.
    public func encode() -> String { JSONValue.array(queries.map(JSONValue.string)).encoded() }

    public var isEmpty: Bool { queries.isEmpty }

    /// With `query` first; the same query (ignoring case and extra spaces)
    /// moves up instead of showing twice. A blank one changes nothing.
    public func adding(_ query: String) -> RecentSearches {
        let q = Self.normalized(query)
        if q.isEmpty { return self }
        return RecentSearches([q] + queries.filter { !Self.same($0, q) })
    }

    public func removing(_ query: String) -> RecentSearches {
        RecentSearches(queries.filter { !Self.same($0, Self.normalized(query)) })
    }

    /// Trimmed, each run of spaces as one.
    static func normalized(_ q: String) -> String { collapsingWhitespace(q).dartTrimmed }

    private static func same(_ a: String, _ b: String) -> Bool { a.lowercased() == b.lowercased() }
}
