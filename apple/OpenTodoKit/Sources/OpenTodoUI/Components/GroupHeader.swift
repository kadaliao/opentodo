// The header of a group of tasks (已过期 / 今天 · 11月26日 周四 / 进行中 /
// 已完成): the title, how many tasks, and a chevron that folds the group
// when `collapsed` is given. 已过期 is red; an empty day is grey.

import OpenTodoDomain
import SwiftUI

public struct GroupHeader: View {
    public var title: String
    public var count: Int?
    public var alert: Bool
    /// Greyed: a group with nothing in it yet (an empty day).
    public var dimmed: Bool
    public var collapsed: Binding<Bool>?
    @Environment(\.uiScale) private var s

    public init(_ title: String, count: Int? = nil, alert: Bool = false, dimmed: Bool = false,
                collapsed: Binding<Bool>? = nil) {
        self.title = title
        self.count = count
        self.alert = alert
        self.dimmed = dimmed
        self.collapsed = collapsed
    }

    public var body: some View {
        let label = HStack(spacing: 6 * s) {
            Text(title)
                .foregroundStyle(alert ? Palette.overdue : (dimmed ? Color.secondary : Color.primary))
            if let count, count > 0 {
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            if let collapsed {
                Image(systemName: "chevron.right")
                    .uiFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed.wrappedValue ? 0 : 90))
            }
        }
        #if os(macOS)
        .uiFont(.subheadline, weight: .semibold)
        #else
        .uiFont(.headline)
        .textCase(nil)
        #endif
        .contentShape(Rectangle())

        if let collapsed {
            Button {
                withAnimation(.snappy) { collapsed.wrappedValue.toggle() }
            } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(collapsed.wrappedValue ? "已收起" : "已展开")
                .accessibilityHint("轻点以\(collapsed.wrappedValue ? "展开" : "收起")")
        } else {
            label.accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
        }
    }
}
