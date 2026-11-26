// Small pieces of the timeline: the checkbox, a bar's face, the date pill,
// colours, and the press-and-drag gesture shared by bars and the 无日期 rows.

import OpenTodoDomain
import SwiftUI

#if os(macOS)
import AppKit
#endif

enum TimelineStyle {
    /// Priority colours, as `app/lib/ui/theme.dart`.
    static func priorityColor(_ p: Priority) -> Color {
        switch p {
        case .high: Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255)
        case .medium: Color(red: 0xF2 / 255, green: 0xA5 / 255, blue: 0x16 / 255)
        case .low: Color(red: 0x3E / 255, green: 0x8B / 255, blue: 0xFF / 255)
        case .none: Color.secondary
        }
    }

    static func title(_ t: TodoTask) -> String { t.title.isEmpty ? "无标题" : t.title }

    static func dayLabel(_ d: Day) -> String { "\(d.month)月\(d.day)日" }

    /// Touch screens drag after a long press, so a swipe still scrolls; a
    /// mouse drags straight away.
    static var touch: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// The keys held right now, for ⌘- and Shift-clicks.
    @MainActor static var modifiers: TapModifiers {
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        var m: TapModifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.shift) { m.insert(.shift) }
        return m
        #else
        return []
        #endif
    }
}

/// A round checkbox in the task's priority colour, as Reminders has.
struct TimelineCheckbox: View {
    let done: Bool
    let priority: Priority
    /// At 标准; it grows with 界面大小.
    var size: Double = 13
    let action: () -> Void
    @Environment(\.uiScale) private var s

    var body: some View {
        let size = size * s
        return Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(done ? Color.secondary : TimelineStyle.priorityColor(priority), lineWidth: 1.4)
                    .background(Circle().fill(priority == .none || done ? Color.clear : TimelineStyle.priorityColor(priority).opacity(0.12)))
                if done {
                    Circle().fill(Color.secondary)
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.55, weight: .bold))
                        .foregroundStyle(.background)
                }
            }
            .frame(width: size, height: size)
            .padding(4 * s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "标记为未完成" : "完成")
        .padding(-4 * s)
    }
}

/// What a bar shows: a tinted strip over the days of the task, its
/// checkbox, title and time when there's room.
struct TimelineBarFace: View {
    @Environment(\.uiScale) private var s
    let task: TodoTask
    let width: Double
    var selected = false
    var overdue = false
    /// Moves the checkbox and title right while the bar's start is off the
    /// left of the screen.
    var shift: Double = 0
    var onToggle: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    private var done: Bool { task.status != .open }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let dark = scheme == .dark
        let fill: Color = done
            ? Color.primary.opacity(dark ? 0.12 : 0.06)
            : Color.accentColor.opacity(selected ? (dark ? 0.55 : 0.34) : (dark ? 0.30 : 0.16))
        HStack(spacing: 6 * s) {
            if width >= TimelineMetrics.checkboxInside {
                TimelineCheckbox(done: done, priority: task.priority, size: 12, action: onToggle)
            }
            if width >= TimelineMetrics.titleInside {
                Text(TimelineStyle.title(task))
                    .uiFont(size: 12, weight: .medium)
                    .strikethrough(done)
                    .foregroundStyle(done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let time = task.dueTime, width >= 120 {
                    Text(timeLabel(time))
                        .uiFont(size: 10) { $0.monospacedDigit() }
                        .foregroundStyle(overdue ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 7 + shift)
        .padding(.trailing, 6)
        .frame(width: width, height: TimelineMetrics.barHeight, alignment: .leading)
        .background {
            // Opaque underneath, so a bar over another (its edge dragged)
            // hides it.
            shape.fill(.background)
            shape.fill(fill)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(done ? Color.secondary.opacity(0.5) : Color.accentColor)
                        .frame(width: 3)
                }
                .clipShape(shape)
        }
        .overlay { if selected { shape.strokeBorder(Color.accentColor, lineWidth: 1.5) } }
    }
}

/// A date said while a bar's edge is dragged.
struct TimelinePill: View {
    let text: String

    var body: some View {
        Text(text)
            .uiFont(size: 11, weight: .semibold)
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor))
    }
}

/// A press that turns into a drag: with a mouse straight away, on a touch
/// screen after a long press (so a swipe still scrolls). A long press let
/// go without moving calls `onStill` (the task's menu). Locations are in
/// the coordinate space `space`.
struct PressDrag: ViewModifier {
    let enabled: Bool
    let space: String
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void
    let onCancelled: () -> Void
    var onStill: () -> Void = {}

    @State private var began = false
    @State private var pressed = false
    @GestureState private var live = false

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else if TimelineStyle.touch {
            content
                .gesture(
                    LongPressGesture(minimumDuration: 0.35)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(space)))
                        .updating($live) { _, state, _ in state = true }
                        .onChanged { value in
                            guard case .second(true, let drag) = value else { return }
                            if !pressed { pressed = true }
                            guard let drag else { return }
                            let moved = hypot(drag.translation.width, drag.translation.height)
                            if !began {
                                // Moving the finger a little after the long
                                // press doesn't start a drag yet.
                                guard moved >= 6 else { return }
                                began = true
                                onBegan(drag.startLocation)
                            }
                            onChanged(drag.location)
                        }
                        .onEnded { value in
                            pressed = false
                            guard case .second(true, let drag) = value else { return }
                            if began, let drag {
                                began = false
                                onEnded(drag.location)
                            } else {
                                began = false
                                onStill()
                            }
                        }
                )
                .sensoryFeedback(.selection, trigger: pressed) { _, now in now }
                .onChange(of: live) { _, now in
                    if !now && began {
                        began = false
                        pressed = false
                        onCancelled()
                    }
                }
        } else {
            content
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named(space))
                        .updating($live) { _, state, _ in state = true }
                        .onChanged { value in
                            if !began {
                                began = true
                                onBegan(value.startLocation)
                            }
                            onChanged(value.location)
                        }
                        .onEnded { value in
                            began = false
                            onEnded(value.location)
                        }
                )
                .onChange(of: live) { _, now in
                    if !now && began {
                        began = false
                        onCancelled()
                    }
                }
        }
    }
}
