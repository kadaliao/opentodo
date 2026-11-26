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
        if let e = list?.emoji, !e.isEmpty { return ViewIcon(.emoji(e), style: style) }
        return ViewIcon(.symbol(ViewSymbol.list, Palette.list(list?.color)), style: style)
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
            Text(e)
        case (.symbol(let name, let color), .badge):
            Image(systemName: name)
                .symbolVariant(.fill)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: Circle())
        case (.emoji(let e), .badge):
            Text(e)
                .font(.system(size: 17))
                .frame(width: 30, height: 30)
                .background(Color.secondary.opacity(0.14), in: Circle())
        }
    }
}
