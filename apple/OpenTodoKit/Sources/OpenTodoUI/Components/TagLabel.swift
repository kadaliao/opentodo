// A tag as text, #工作, in the accent colour: how the rows and the detail
// show tags (system apps write tags this way rather than as chips).

import OpenTodoDomain
import SwiftUI

public struct TagLabel: View {
    public var tag: String
    /// `.increased` in a selected row on the Mac (white text on the accent
    /// colour), where the accent-coloured tag wouldn't show.
    @Environment(\.backgroundProminence) private var prominence

    public init(_ tag: String) { self.tag = tag }

    public var body: some View {
        Text("#\(tag)")
            .foregroundStyle(prominence == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            .lineLimit(1)
            .accessibilityLabel("标签 \(tag)")
    }
}

/// Tags in a row, with a capsule behind each: the detail's tag field.
public struct TagChips: View {
    public var tags: [String]

    public init(_ tags: [String]) { self.tags = tags }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.14), in: Capsule())
                    .foregroundStyle(.tint)
                    .accessibilityLabel("标签 \(tag)")
            }
        }
    }
}
