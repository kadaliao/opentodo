// What Spotlight finds: each open task (not in the trash) with its list,
// date and the start of its notes, and its tags as keywords. The app
// indexes these with CoreSpotlight (`OpenTodoUI/System/Spotlight.swift`);
// a result opens the task (`AppLink.task`).

import Foundation
import OpenTodoDomain

public struct SpotlightEntry: Hashable, Sendable {
    public var id: String
    public var title: String
    /// 工作 · 明天, 下午3:00 · the first line of the notes.
    public var details: String
    public var keywords: [String]

    public init(id: String, title: String, details: String, keywords: [String]) {
        self.id = id
        self.title = title
        self.details = details
        self.keywords = keywords
    }
}

public func spotlightEntries(_ tasks: [TodoTask], lists: [TaskList], today: Day) -> [SpotlightEntry] {
    let byId = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    return tasks.filter(isOpen).map { t in
        var parts = [listName(t.listId, byId)]
        if let due = t.dueDate { parts.append(fullDueLabel(due, t.dueTime, today: today, duration: t.duration)) }
        let note = t.content.split(whereSeparator: \.isNewline).first.map { String($0.prefix(120)) }
        if let note, !note.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(note) }
        return SpotlightEntry(id: t.id, title: t.title.isEmpty ? "无标题" : t.title,
                              details: parts.joined(separator: " · "), keywords: t.tags)
    }
}
