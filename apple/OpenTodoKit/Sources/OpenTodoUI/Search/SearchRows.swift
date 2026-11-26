// Rows of the search results, shared by the macOS panel and the iOS page.

import OpenTodoDomain
import SwiftUI

/// `text` with the UTF-16 `ranges` marked in yellow, as Mail and Notes mark
/// what was searched for.
func highlighted(_ text: String, _ ranges: TextRanges, mark: Color) -> AttributedString {
    var out = AttributedString()
    let utf16 = text.utf16
    var pos = 0
    func piece(_ a: Int, _ b: Int) -> AttributedString {
        let start = utf16.index(utf16.startIndex, offsetBy: a)
        let end = utf16.index(utf16.startIndex, offsetBy: b)
        return AttributedString(String(text[start..<end]))
    }
    for r in ranges {
        // Ranges are sorted and don't overlap; skip anything that doesn't fit.
        guard r.lowerBound >= pos, r.upperBound <= utf16.count else { continue }
        // A range that cuts a surrogate pair would make a broken string.
        let start = utf16.index(utf16.startIndex, offsetBy: r.lowerBound)
        let end = utf16.index(utf16.startIndex, offsetBy: r.upperBound)
        guard start.samePosition(in: text.unicodeScalars) != nil,
              end.samePosition(in: text.unicodeScalars) != nil
        else { continue }
        if r.lowerBound > pos { out += piece(pos, r.lowerBound) }
        var hit = piece(r.lowerBound, r.upperBound)
        hit.backgroundColor = mark
        out += hit
        pos = r.upperBound
    }
    if pos < utf16.count { out += piece(pos, utf16.count) }
    return out
}

/// The yellow behind matched text, toned down in dark mode.
struct SearchMark {
    static func color(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.72, green: 0.53, blue: 0.04).opacity(0.55)
            : Color(red: 1, green: 0.88, blue: 0.54)
    }
}


/// A list, filter or tag found by name.
struct SearchViewRow: View {
    @Environment(\.uiScale) private var s
    let entry: SearchEntry
    let terms: [String]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10 * s) {
            icon
                .frame(width: 22 * s)
            Text(highlighted(label, findRanges(label, terms), mark: SearchMark.color(scheme)))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var label: String {
        switch entry {
        case .list(let l): l.name
        case .filter(let f): f.name
        case .tag(let t): t
        default: ""
        }
    }

    @ViewBuilder private var icon: some View {
        switch entry {
        case .list(let l):
            if let emoji = l.emoji, !emoji.isEmpty {
                Text(emoji)
            } else {
                Image(systemName: "list.bullet").foregroundStyle(.secondary)
            }
        case .filter:
            Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
        case .tag:
            Image(systemName: "number").foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

/// A task found: tick box, title with the words marked, the line that
/// shows why it was found, and where it lives and when it's due.
struct SearchTaskRow: View {
    @Environment(\.uiScale) private var s
    let hit: TaskHit
    let lists: [String: TaskList]
    let now: LocalDateTime
    let onToggleDone: (TodoTask, Bool) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let task = hit.task
        let done = task.status != .open
        let mark = SearchMark.color(scheme)
        HStack(alignment: .firstTextBaseline, spacing: 10 * s) {
            PriorityCheckbox(checked: done, priority: task.priority) { onToggleDone(task, !done) }
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(task.title.isEmpty
                    ? AttributedString("无标题")
                    : highlighted(task.title, hit.titleRanges, mark: mark))
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done || task.title.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                if let snippet = hit.snippet {
                    Text(highlighted(snippet, hit.snippetRanges, mark: mark))
                        .uiFont(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2 * s) {
                Text(listLabel)
                if let due = task.dueDate {
                    Text(dueLabel(due, task.dueTime, today: now.day, duration: task.duration))
                        .foregroundStyle(isOverdue(task, now) ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
            }
            .uiFont(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private var listLabel: String {
        guard hit.task.listId != inboxListId, let list = lists[hit.task.listId] else { return "收集箱" }
        return "\(list.emoji ?? "") \(list.name)".trimmingCharacters(in: .whitespaces)
    }
}

/// A recent search, shown before anything is typed.
struct SearchRecentRow: View {
    @Environment(\.uiScale) private var s
    let query: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10 * s) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .frame(width: 22 * s)
            Text(query).lineLimit(1)
            Spacer(minLength: 0)
            #if os(macOS)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .uiFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("从最近搜索中移除")
            .accessibilityLabel("移除")
            #endif
        }
        .contentShape(Rectangle())
    }
}

/// Nothing typed yet, or nothing found.
struct SearchPlaceholder: View {
    let model: SearchModel

    var body: some View {
        if model.phase == .noResults {
            ContentUnavailableView {
                Label(model.noResultsTitle, systemImage: "magnifyingglass")
            } description: {
                Text("垃圾桶里的任务不在搜索范围内")
            }
        } else {
            ContentUnavailableView {
                Label("搜索任务、清单、标签和过滤器", systemImage: "text.magnifyingglass")
            } description: {
                Text("会查找标题、描述和子任务；多个词用空格隔开")
            }
        }
    }
}
