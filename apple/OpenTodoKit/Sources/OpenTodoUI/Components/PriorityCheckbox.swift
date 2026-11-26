// The round checkbox at the start of a task row: its ring is the task's
// priority colour (grey for none, with a faint fill of the colour for the
// others); a finished task shows a filled grey check. Hit area is at least
// 28pt on iOS (20pt on macOS) even though the circle is smaller. Both grow
// with 界面大小 (`size` is the size at 标准).

import OpenTodoDomain
import SwiftUI

public struct PriorityCheckbox: View {
    public var checked: Bool
    public var priority: Priority
    public var size: CGFloat
    public var action: (() -> Void)?
    @Environment(\.uiScale) private var scale

    public init(checked: Bool, priority: Priority, size: CGFloat = PriorityCheckbox.defaultSize, action: (() -> Void)? = nil) {
        self.checked = checked
        self.priority = priority
        self.size = size
        self.action = action
    }

    /// At 标准; `size` and the hit area grow with 界面大小.
    #if os(macOS)
    public static let defaultSize: CGFloat = 16
    static let minHit: CGFloat = 20
    #else
    public static let defaultSize: CGFloat = 22
    static let minHit: CGFloat = 28
    #endif

    public var body: some View {
        Button {
            action?()
        } label: {
            let hit = max(size, Self.minHit) * scale
            mark
                .frame(width: hit, height: hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel(checked ? "标记为未完成" : "完成")
        .accessibilityValue(checked ? "已完成" : priorityName(priority))
        .accessibilityAddTraits(checked ? [.isSelected] : [])
    }

    private var mark: some View {
        let size = size * scale
        let color = Palette.priority(priority)
        let line = max(1.2, size / 12)
        return ZStack {
            if checked {
                Circle().fill(Color.secondary.opacity(0.55))
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.background)
            } else {
                Circle().fill(priority == .none ? Color.clear : color.opacity(0.12))
                Circle().strokeBorder(priority == .none ? Color.secondary.opacity(0.6) : color, lineWidth: line)
            }
        }
        .frame(width: size, height: size)
        .animation(.snappy(duration: 0.15), value: checked)
    }
}

#Preview {
    HStack {
        ForEach(Priority.allCases, id: \.self) { p in
            PriorityCheckbox(checked: false, priority: p) {}
        }
        PriorityCheckbox(checked: true, priority: .high) {}
    }
    .padding()
}
