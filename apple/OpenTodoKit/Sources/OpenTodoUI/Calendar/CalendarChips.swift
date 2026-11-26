// A task on the calendar: a tinted bar in a month cell or the all-day row
// (one bar across the days a span covers), a block on the hour grid as
// tall as the task is long. Both open the task on a click (or pick it
// with ⌘ / Shift), tick it with their checkbox, show its menu on a
// right-click or a long press, and drag to another day or time. A later
// date of a repeating task (projected) is faded with a repeat mark: it
// opens the task but can't be ticked or moved. Port of `entry_chip.dart`.

import OpenTodoDomain
import SwiftUI
import UniformTypeIdentifiers

/// How an entry is drawn, from its state.
struct ChipStyle {
    let fill: Color
    let stroke: Color?
    let dashed: Bool
    let text: AnyShapeStyle
    let stripe: Color

    init(_ e: CalendarEntry, tint: Color, selected: Bool, dragging: Bool) {
        if e.done {
            fill = Color.secondary.opacity(0.12)
            stroke = nil
            dashed = false
            text = AnyShapeStyle(.secondary)
            stripe = Color.secondary.opacity(0.5)
        } else if e.projected {
            fill = tint.opacity(0.07)
            stroke = tint.opacity(0.55)
            dashed = true
            text = AnyShapeStyle(.secondary)
            stripe = tint.opacity(0.5)
        } else if selected {
            fill = tint.opacity(0.42)
            stroke = tint
            dashed = false
            text = AnyShapeStyle(.primary)
            stripe = tint
        } else {
            fill = tint.opacity(0.2)
            stroke = nil
            dashed = false
            text = AnyShapeStyle(.primary)
            stripe = tint
        }
        _ = dragging
    }
}

/// The interactions every chip has: open / pick on a click, the menu, the
/// drag.
struct ChipInteractions: ViewModifier {
    let entry: CalendarEntry
    let ctx: CalendarContext
    /// The tasks in the order shown, for Shift-click.
    let order: [String]

    @ViewBuilder func body(content: Content) -> some View {
        let model = ctx.model
        let movable = CalendarLogic.canMoveEntry(entry)
        let along = model.drag.map { $0.count > 1 && $0.has(entry.task.id) } ?? false
        let base = content
            .contentShape(Rectangle())
            .onTapGesture { tap() }
            .opacity(along && model.hover != nil ? 0.35 : 1)
            .contextMenu {
                if !entry.projected {
                    if let menu = ctx.options.taskMenu { menu(entry.task) }
                    Button {
                        model.selection.start(entry.task.id)
                    } label: {
                        Label("多选", systemImage: "checkmark.circle")
                    }
                }
            }
            .accessibilityAction(named: "打开") { ctx.actions.openTask(entry.task.id) }
            .calendarCardPopover(ctx, entryKey: entry.key)
        if movable {
            base.onDrag {
                model.beginDrag(entry, others: ctx.dragAlong(entry))
                return NSItemProvider(object: CalendarDragSession.marker as NSString)
            } preview: {
                ChipDragPreview(entry: entry, ctx: ctx)
            }
        } else {
            base
        }
    }

    private func tap() {
        let model = ctx.model
        guard let id = model.selection.tap(
            entry.task.id, modifiers: currentClickModifiers(), order: order, current: model.openTaskId
        ) else { return }
        switch ctx.taskTap {
        case .open: ctx.actions.openTask(id)
        case .card: model.openCard(id, at: entry.key)
        }
    }
}

/// What follows the pointer while an entry is dragged: the bar, with how
/// many go along.
struct ChipDragPreview: View {
    let entry: CalendarEntry
    let ctx: CalendarContext

    var body: some View {
        let count = ctx.dragAlong(entry).count + 1
        let tint = ctx.color(of: entry.task)
        HStack(spacing: 6) {
            Text(entry.task.title.isEmpty ? "无标题" : entry.task.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if count > 1 {
                Text(verbatim: "\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(tint))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.3)))
        .background(RoundedRectangle(cornerRadius: 5).fill(.background))
    }
}

/// A task as a bar: in a month cell, the multi-week grid or the all-day
/// row. `columns` > 1 draws one bar across that many days; the ends that go
/// on into another row are left square.
struct EntryBar: View {
    let entry: CalendarEntry
    let ctx: CalendarContext
    let order: [String]
    var showTime = true
    var openStart = false
    var openEnd = false

    var body: some View {
        let task = entry.task
        let tint = ctx.color(of: task)
        let style = ChipStyle(entry, tint: tint, selected: ctx.isSelected(entry), dragging: false)
        let overdue = !entry.projected && !entry.done && isOverdue(task, ctx.now)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: openStart ? 0 : 4, bottomLeadingRadius: openStart ? 0 : 4,
            bottomTrailingRadius: openEnd ? 0 : 4, topTrailingRadius: openEnd ? 0 : 4
        )
        HStack(spacing: 2) {
            mark(tint: tint, style: style)
            Text(task.title.isEmpty ? "无标题" : task.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(style.text)
                .strikethrough(entry.done)
                .lineLimit(1)
            Spacer(minLength: 0)
            if showTime, let time = entry.time, entry.dayIndex == 0 {
                Text(timeLabel(time))
                    .font(.system(size: 10))
                    .foregroundStyle(overdue ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.leading, 1)
        .padding(.trailing, 4)
        .frame(height: CalendarMetrics.chipHeight)
        .background(shape.fill(style.fill))
        .overlay {
            if let stroke = style.stroke {
                shape.strokeBorder(stroke, style: StrokeStyle(lineWidth: style.dashed ? 1 : 1.5, dash: style.dashed ? [3, 2] : []))
            }
        }
        .modifier(ChipInteractions(entry: entry, ctx: ctx, order: order))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility)
    }

    @ViewBuilder private func mark(tint: Color, style: ChipStyle) -> some View {
        if entry.projected {
            Image(systemName: "repeat")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityLabel("重复")
        } else {
            PriorityCheckbox(checked: entry.done, priority: entry.task.priority, size: 11) {
                ctx.actions.setDone(entry.task.id, !entry.done)
            }
            .disabled(entry.task.trashedAt != nil)
        }
    }

    private var accessibility: String {
        var parts = [entry.task.title.isEmpty ? "无标题" : entry.task.title]
        if let t = entry.time { parts.append(timeLabel(t)) }
        if entry.done { parts.append("已完成") }
        if entry.projected { parts.append("重复") }
        return parts.joined(separator: "，")
    }
}

/// A task on the hour grid, as tall as it is long (half an hour for a
/// task at one moment). A tall one says when it starts and ends; while its
/// bottom edge is dragged, it says where it will end.
struct TimedBlock: View {
    let placement: TimedPlacement
    let ctx: CalendarContext
    let order: [String]
    let height: CGFloat
    /// Where the bottom edge is being dragged to.
    var resizingTo: Int?

    var body: some View {
        let entry = placement.entry
        let task = entry.task
        let tint = ctx.color(of: task)
        let style = ChipStyle(entry, tint: tint, selected: ctx.isSelected(entry), dragging: false)
        let overdue = !entry.projected && !entry.done && isOverdue(task, ctx.now)
        let tall = height > 26
        HStack(alignment: tall ? .top : .center, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5).fill(style.stripe).frame(width: 3)
                .padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .center, spacing: 2) {
                    if entry.projected {
                        Image(systemName: "repeat").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(width: 16)
                    } else {
                        PriorityCheckbox(checked: entry.done, priority: task.priority, size: 11) {
                            ctx.actions.setDone(task.id, !entry.done)
                        }
                    }
                    Text(task.title.isEmpty ? "无标题" : task.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(style.text)
                        .strikethrough(entry.done)
                        .lineLimit(1)
                    if let resizingTo {
                        Spacer(minLength: 2)
                        Text(verbatim: "→ \(clockLabel(resizingTo))").font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
                    }
                }
                if height >= 40, let start = entry.time {
                    let end = entry.endTime
                    Text(end.map { "\(clockLabel(start))-\(clockLabel($0))" } ?? clockLabel(start))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(overdue ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.leading, 18)
                }
            }
            .padding(.top, tall ? 2 : 0)
            Spacer(minLength: 0)
        }
        .frame(height: height, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 4).fill(style.fill))
        .background(RoundedRectangle(cornerRadius: 4).fill(.background).opacity(entry.projected ? 0 : 0.6))
        .overlay {
            if let stroke = style.stroke {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(stroke, style: StrokeStyle(lineWidth: style.dashed ? 1 : 1.5, dash: style.dashed ? [3, 2] : []))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .modifier(ChipInteractions(entry: entry, ctx: ctx, order: order))
        .accessibilityElement(children: .combine)
    }
}

/// The strip along the bottom of a block on the hour grid that drags its
/// end up or down (snapping to 15 minutes).
struct ResizeHandle: View {
    let placement: TimedPlacement
    let ctx: CalendarContext

    var body: some View {
        Color.clear
            .frame(height: 8)
            .contentShape(Rectangle())
            #if os(macOS)
            .pointerStyle(.frameResize(position: .bottom))
            #endif
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { g in
                        let end = CalendarLogic.resizedEnd(start: placement.start, end: placement.end, dy: g.translation.height)
                        if ctx.model.resize?.end != end || ctx.model.resize?.key != placement.entry.key {
                            ctx.model.resize = (placement.entry.key, end)
                        }
                    }
                    .onEnded { _ in
                        let end = ctx.model.resize?.end
                        ctx.model.resize = nil
                        guard let end, end != placement.end,
                              let minutes = CalendarLogic.durationForEnd(placement.entry, end: end) else { return }
                        ctx.actions.setDuration(placement.entry.task.id, minutes)
                    }
            )
            .accessibilityLabel("拖动改结束时间")
    }
}

// MARK: - Drop targets

/// One drop target over a whole grid (the month, the all-day row, the
/// hour grid): it works out the day (and minute) from where the pointer
/// is, keeps the hover box up to date, and on a drop hands the moves to
/// the app, unless the drag ended where it began.
struct CalendarDropDelegate: DropDelegate {
    let ctx: CalendarContext
    /// Names this target's coordinate space (for the in-place check).
    let space: String
    /// What a point in this target means: a hover target, or nil outside it.
    let resolve: (CGPoint, CalendarDragSession) -> CalendarHover.Target?

    func validateDrop(info: DropInfo) -> Bool { ctx.model.drag != nil }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if ctx.model.hover != nil { ctx.model.hover = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let model = ctx.model
        defer { model.endDrag() }
        guard let drag = model.drag else { return false }
        if model.dropIsInPlace(info.location, in: space) { return true }
        guard let target = resolve(info.location, drag) else { return false }
        let moves: [CalendarMove] = switch target {
        case .cell(let day): drag.moves(to: day)
        case .allDay(let day): drag.moves(to: day, allDay: true)
        case .grid(let day, let minute, _): drag.moves(to: day, minute: minute)
        }
        let changed = moves.filter { m in
            ctx.tasks.first { $0.id == m.id }.map { $0.dueDate != m.date || $0.dueTime != m.time } ?? true
        }
        if !changed.isEmpty { ctx.actions.move(changed) }
        return true
    }

    private func update(_ info: DropInfo) {
        let model = ctx.model
        model.dragSeen(at: info.location, in: space)
        guard let drag = model.drag else { return }
        let target = resolve(info.location, drag)
        let hover = target.map { CalendarHover(target: $0, count: drag.count) }
        if model.hover != hover { model.hover = hover }
    }
}

extension View {
    /// Takes calendar drags (and nothing else) over this view.
    func calendarDropTarget(_ delegate: CalendarDropDelegate) -> some View {
        onDrop(of: [UTType.plainText, UTType.utf8PlainText, UTType.text], delegate: delegate)
    }
}
