// Where a drag would land: the places that take a drop (slots), measured in
// the drag space's coordinates, and the pure hit test from a pointer
// position to a landing place and the hint drawn for it. Kept free of views
// so it can be unit tested; `DragController` feeds it the live geometry.
//
// The rules (`app/lib/ui/task_drag.dart`, `section_actions.dart`):
//
// - A task row or card: dropped on its top half it goes before the row, on
//   its bottom half after it. A line shows where.
// - An area (a group's header, the space under a board column's cards)
//   takes tasks at a fixed place: a header puts them first, the end space
//   last. The area lights up.
// - A group that isn't in manual order only changes what group the tasks
//   are in: the whole group lights up and no line is drawn, and its own
//   tasks don't drop on it.
// - A section's header (or board column) takes another section of its list
//   before or after it: above or below a header, left or right of a column.
//   No line when that would leave the section where it is.

import CoreGraphics
import OpenTodoDomain
import SwiftUI

/// What a place takes, and where.
public enum DropSlotKind: Hashable, Sendable {
    /// A row or card of `group` at `index` among its tasks.
    case taskRow(GroupDrop, index: Int)
    /// A place that takes tasks into `group` at `index`.
    case taskArea(GroupDrop, index: Int)
    /// A section's header (`axis` vertical) or board column (horizontal),
    /// `among` its list's sections in order.
    case section(ListSection, among: [ListSection], axis: Axis)
}

/// A place that takes a drop, and where it is in the drag space.
public struct DropSlot: Hashable, Sendable, Identifiable {
    public var id: String
    public var frame: CGRect
    public var kind: DropSlotKind

    public init(id: String, frame: CGRect, kind: DropSlotKind) {
        self.id = id
        self.frame = frame
        self.kind = kind
    }

    var takesTasks: Bool {
        if case .section = kind { false } else { true }
    }
}

/// The hint shown while something hovers.
public enum DropIndicator: Hashable, Sendable {
    case none
    /// An insertion line between two points of the drag space.
    case line(CGPoint, CGPoint)
    /// The area under the pointer lights up.
    case area(CGRect)
    /// The whole group lights up (its views draw that themselves).
    case group(GroupTarget)
}

/// What letting go would do.
public enum DropAction: Hashable, Sendable {
    /// The dragged tasks go into `group` at `index`.
    case tasks(GroupDrop, index: Int)
    /// The section `id` goes to `index` of `among`.
    case section(String, to: Int, among: [ListSection])
}

/// Where a drag hovers: the slot, what a drop does, and the hint.
public struct DropHover: Hashable, Sendable {
    public var slotId: String
    public var action: DropAction
    public var indicator: DropIndicator

    /// The group a task drop goes into.
    public var group: GroupTarget? {
        if case .tasks(let g, _) = action { g.target } else { nil }
    }
}

/// What a drop comes to, ready for whoever writes it.
public enum DropOutcome: Hashable, Sendable {
    case tasks(TaskDropPlan)
    /// New `sortOrder`s of a list's sections.
    case sections([String: Double])
}

extension DropHover {
    /// What dropping `item` here does; nil when nothing changes.
    public func outcome(for item: DragItem) -> DropOutcome? {
        switch (action, item) {
        case let (.tasks(group, index), .tasks(d)):
            return group.plan(d, at: index).map(DropOutcome.tasks)
        case let (.section(id, to, among), .section):
            let orders = planSectionMove(among, id, to: to)
            return orders.isEmpty ? nil : .sections(orders)
        default:
            return nil
        }
    }
}

/// Where `item` would land with the pointer at `p`, among `slots` (frames
/// already cut to what's visible); nil when nothing there takes it. Where
/// slots overlap, the smallest wins.
public func resolveDrop(_ item: DragItem, at p: CGPoint, in slots: [DropSlot]) -> DropHover? {
    let wantsTasks = if case .tasks = item { true } else { false }
    let hit = slots
        .filter { $0.takesTasks == wantsTasks && !$0.frame.isEmpty && $0.frame.contains(p) }
        .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    guard let slot = hit else { return nil }
    let f = slot.frame
    switch (slot.kind, item) {
    case let (.taskRow(group, index), .tasks(d)):
        guard group.accepts(d) else { return nil }
        let before = p.y < f.midY
        let y = before ? f.minY : f.maxY
        return DropHover(
            slotId: slot.id,
            action: .tasks(group, index: before ? index : index + 1),
            indicator: group.ordered ? .line(CGPoint(x: f.minX, y: y), CGPoint(x: f.maxX, y: y)) : .group(group.target)
        )
    case let (.taskArea(group, index), .tasks(d)):
        guard group.accepts(d) else { return nil }
        return DropHover(
            slotId: slot.id,
            action: .tasks(group, index: index),
            indicator: group.ordered ? .area(f) : .group(group.target)
        )
    case let (.section(section, among, axis), .section(dragged)):
        guard dragged.listId == section.listId, dragged.id != section.id,
              let at = among.firstIndex(where: { $0.id == section.id })
        else { return nil }
        let before = axis == .vertical ? p.y < f.midY : p.x < f.midX
        let to = before ? at : at + 1
        let from = among.firstIndex { $0.id == dragged.id }
        let stays = from.map { to == $0 || to == $0 + 1 } ?? false
        let indicator: DropIndicator = if stays {
            .none
        } else if axis == .vertical {
            .line(CGPoint(x: f.minX, y: before ? f.minY : f.maxY), CGPoint(x: f.maxX, y: before ? f.minY : f.maxY))
        } else {
            .line(CGPoint(x: before ? f.minX : f.maxX, y: f.minY), CGPoint(x: before ? f.minX : f.maxX, y: f.maxY))
        }
        return DropHover(slotId: slot.id, action: .section(dragged.id, to: to, among: among), indicator: indicator)
    default:
        return nil
    }
}

/// How far to scroll a view per frame while a drag is at `p` near the
/// edges of its `viewport` along `axis`: up to `maxStep` points right at
/// (or past) the edge, easing off to nothing `edge` points in, negative
/// toward the start. Zero when `p` isn't over the viewport (it may be up
/// to `edge` past its ends along the axis, over a header, say).
public func edgeScrollStep(
    _ p: CGPoint, in viewport: CGRect, axis: Axis, edge: CGFloat = 56, maxStep: CGFloat = 14
) -> CGFloat {
    guard !viewport.isEmpty else { return 0 }
    let (pos, cross, lo, hi, crossLo, crossHi) = axis == .vertical
        ? (p.y, p.x, viewport.minY, viewport.maxY, viewport.minX, viewport.maxX)
        : (p.x, p.y, viewport.minX, viewport.maxX, viewport.minY, viewport.maxY)
    guard cross >= crossLo, cross <= crossHi, pos >= lo - edge, pos <= hi + edge else { return 0 }
    // A viewport too small for both edges uses half of it for each.
    let reach = min(edge, (hi - lo) / 2)
    guard reach > 0 else { return 0 }
    func speed(_ depth: CGFloat) -> CGFloat { maxStep * min(1, max(0, 1 - depth / reach)) }
    if pos < lo + reach { return -speed(pos - lo) }
    if pos > hi - reach { return speed(hi - pos) }
    return 0
}

/// Where a scroll view's offset goes after `step` points, kept within its
/// content.
public func clampedScrollOffset(_ offset: CGFloat, by step: CGFloat, content: CGFloat, viewport: CGFloat) -> CGFloat {
    min(max(offset + step, 0), max(0, content - viewport))
}
