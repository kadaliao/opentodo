// The icon of a smart list, list, filter or tag: an emoji when the list
// has one, otherwise an SF Symbol in the view's colour.
//
// `.plain` is for sidebars (an outline symbol, like Mail's, coloured by
// the row's `.listItemTint(icon.tint)`);
// `.badge` is for iOS lists (a white glyph on a coloured circle, an emoji
// on a light grey one, like the system's own list screens).

import OpenTodoDomain
import SwiftUI

public struct ViewIcon: View {
    @Environment(\.uiScale) private var s
    public enum Content: Hashable {
        case symbol(String, Color)
        case emoji(String)
    }

    public enum Style { case plain, badge }

    public var content: Content
    public var style: Style

    public init(_ content: Content, style: Style = .plain) {
        self.content = content
        self.style = style
    }

    public static func smart(_ kind: SmartKind, style: Style = .plain) -> ViewIcon {
        ViewIcon(.symbol(kind.symbol, kind.tint), style: style)
    }

    public static func list(_ list: TaskList?, style: Style = .plain) -> ViewIcon {
        switch list?.icon {
        case .emoji(let e)?: return ViewIcon(.emoji(e), style: style)
        case .symbol(let name)?: return ViewIcon(.symbol(name, Palette.list(list?.color)), style: style)
        case nil: return ViewIcon(.symbol(ViewSymbol.list, Palette.list(list?.color)), style: style)
        }
    }

    public static func filter(style: Style = .plain) -> ViewIcon {
        ViewIcon(.symbol(ViewSymbol.filter, .teal), style: style)
    }

    public static func tag(style: Style = .plain) -> ViewIcon {
        ViewIcon(.symbol(ViewSymbol.tag, .gray), style: style)
    }

    /// The colour for `.listItemTint` (plain symbols take it from there).
    public var tint: Color? {
        if case .symbol(_, let color) = content { color } else { nil }
    }

    public var body: some View {
        switch (content, style) {
        case (.symbol(let name, _), .plain):
            // Coloured by the row's `.listItemTint(icon.tint)`, so a
            // selected sidebar row can turn it white.
            Image(systemName: name)
        case (.emoji(let e), .plain):
            // A typed-in character or two (`ListIcon.custom`) fits the
            // symbol's box.
            if e.count > 1 {
                Text(e).uiFont(.caption2, weight: .semibold).lineLimit(1).minimumScaleFactor(0.6)
            } else {
                Text(e)
            }
        case (.symbol(let name, let color), .badge):
            Image(systemName: name)
                .symbolVariant(.fill)
                .uiFont(size: 14, weight: .semibold)
                .foregroundStyle(.white)
                .frame(width: 30 * s, height: 30 * s)
                .background(color.gradient, in: Circle())
        case (.emoji(let e), .badge):
            Text(e)
                .uiFont(size: e.count > 1 ? 12 : 17, weight: e.count > 1 ? .semibold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 30 * s, height: 30 * s)
                .background(Color.secondary.opacity(0.14), in: Circle())
        }
    }
}

/// A list's name with its icon, for menus and pickers: a symbol as the
/// item's image, an emoji (or `fallback`) before the name.
@ViewBuilder
func listMenuLabel(_ l: TaskList, fallback: String? = "📋") -> some View {
    switch l.icon {
    case .symbol(let name)?: Label(l.name, systemImage: name)
    case .emoji(let e)?: Text("\(e) \(l.name)")
    case nil:
        if let fallback { Text("\(fallback) \(l.name)") } else { Text(l.name) }
    }
}
