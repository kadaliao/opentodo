// A task on the board: its box and title, then its date, marks, tags and
// checklist progress.

import OpenTodoDomain
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Board colours: system ones, a little different on each platform.
enum BoardStyle {
    static var cardFill: Color {
        #if os(macOS)
        // White in light mode; in dark mode a step above the column.
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.2, alpha: 1) : .white
        })
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    static var boardBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static let cardRadius: CGFloat = 12
    static let columnRadius: CGFloat = 16

    /// `app/lib/ui/theme.dart`'s priority colours.
    static func priority(_ p: Priority) -> Color {
        switch p {
        case .high: Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255)
        case .medium: Color(red: 0xF2 / 255, green: 0xA5 / 255, blue: 0x16 / 255)
        case .low: Color(red: 0x3E / 255, green: 0x8B / 255, blue: 0xFF / 255)
        case .none: Color.secondary
        }
    }
}

/// The keys held right now (⌘ / ⇧ clicks pick cards on a Mac).
@MainActor func currentModifiers() -> EventModifiers {
    #if os(macOS)
    let flags = NSEvent.modifierFlags
    var m: EventModifiers = []
    if flags.contains(.command) { m.insert(.command) }
    if flags.contains(.shift) { m.insert(.shift) }
    if flags.contains(.option) { m.insert(.option) }
    if flags.contains(.control) { m.insert(.control) }
    return m
    #else
    return []
    #endif
}

/// The round box that ticks a task off, ringed in its priority's colour.
struct TaskCheckbox: View {
    let done: Bool
    let priority: Priority
    let toggle: () -> Void
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 18

    var body: some View {
        Button(action: toggle) {
            ZStack {
                Circle()
                    .fill(done ? Color.secondary.opacity(0.5) : BoardStyle.priority(priority).opacity(priority == .none ? 0 : 0.12))
                Circle()
                    .strokeBorder(done ? Color.clear : BoardStyle.priority(priority), lineWidth: 1.5)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.55, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "标记为未完成" : "完成")
        .accessibilityAddTraits(done ? .isSelected : [])
    }
}

struct BoardCard: View {
    let task: TodoTask
    let selected: Bool
    let now: LocalDateTime
    let progress: ChecklistProgress?
    let toggle: () -> Void

    private var done: Bool { task.status != .open }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            TaskCheckbox(done: done, priority: task.priority, toggle: toggle)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title.isEmpty ? "无标题" : task.title)
                    .font(.body)
                    .foregroundStyle(done || task.title.isEmpty ? .secondary : .primary)
                    .strikethrough(done, color: .secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hasMeta { meta }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: BoardStyle.cardRadius, style: .continuous)
                .fill(selected ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(BoardStyle.cardFill))
                .shadow(color: .black.opacity(selected ? 0 : 0.06), radius: 1, y: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: BoardStyle.cardRadius, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.06), lineWidth: selected ? 1 : 0.5)
        }
        .opacity(done ? 0.75 : 1)
        .contentShape(RoundedRectangle(cornerRadius: BoardStyle.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: done ? "标记为未完成" : "完成", toggle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var pinned: Bool { task.pinnedAt != nil && !done }

    private var hasMeta: Bool {
        task.dueDate != nil || !task.tags.isEmpty || pinned || (progress.map { $0.total > 0 } ?? false)
    }

    private var meta: some View {
        let overdue = isOverdue(task, now)
        let dueColor: Color = done ? .secondary : (overdue ? .red : .accentColor)
        return FlowLayout(spacing: 6, lineSpacing: 4) {
            if pinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("已置顶")
            }
            if let due = task.dueDate {
                HStack(spacing: 3) {
                    if !task.reminders.isEmpty && !done {
                        Image(systemName: "alarm").accessibilityLabel("有提醒")
                    }
                    if task.repeatRule != nil {
                        Image(systemName: "repeat").accessibilityLabel("重复")
                    }
                    Text(dueLabel(due, task.dueTime, today: now.day, duration: task.duration))
                        .fontWeight(overdue ? .semibold : nil)
                }
                .foregroundStyle(dueColor)
            }
            if let progress, progress.total > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "checklist")
                    Text("\(progress.done)/\(progress.total)").monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("子任务 \(progress.done)/\(progress.total)")
            }
            ForEach(task.tags, id: \.self) { tag in
                Text(tag)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.caption)
    }
}

/// Lays its children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty && needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
