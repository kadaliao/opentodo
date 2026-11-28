// A list's icon, as its `emoji` column holds it (the column and the sync
// format stay as they were; only what's written in them grew):
//
// - an emoji, or a character or two typed in (“A”, “工作”'s “工”): shown
//   as text;
// - `sf:<name>`: an SF Symbol, drawn in the list's colour (`TaskList.color`).
//
// The Flutter version shows an `sf:` value as no icon at all (its default),
// not as the text (`app/lib/domain/list_icon.dart`).
//
//     list.icon            // .emoji("💼") / .symbol("briefcase") / nil
//     list.textEmoji       // "💼" for text before a name; nil for a symbol
//     ListIcon.custom(" AI ")  // .emoji("AI"): at most two characters

import Foundation

public enum ListIcon: Hashable, Sendable {
    case emoji(String)
    case symbol(String)

    public static let symbolPrefix = "sf:"

    /// Most characters a typed-in icon keeps.
    public static let maxCharacters = 2

    /// The icon `stored` (a list's `emoji`) stands for; nil for none.
    public init?(stored: String?) {
        guard let stored, !stored.isEmpty else { return nil }
        if stored.hasPrefix(Self.symbolPrefix) {
            let name = String(stored.dropFirst(Self.symbolPrefix.count))
            guard !name.isEmpty else { return nil }
            self = .symbol(name)
        } else {
            self = .emoji(stored)
        }
    }

    /// What goes in the `emoji` column.
    public var stored: String {
        switch self {
        case .emoji(let e): e
        case .symbol(let name): Self.symbolPrefix + name
        }
    }

    /// An icon typed in: the first two characters, spaces trimmed; nil
    /// when nothing's left.
    public static func custom(_ text: String) -> ListIcon? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = String(trimmed.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
        return kept.isEmpty ? nil : .emoji(kept)
    }
}

extension TaskList {
    public var icon: ListIcon? { ListIcon(stored: emoji) }

    /// The icon as text to put before the list's name (menus, pickers, the
    /// share sheet); nil when there's none or it's a symbol.
    public var textEmoji: String? {
        if case .emoji(let e)? = icon { e } else { nil }
    }
}
