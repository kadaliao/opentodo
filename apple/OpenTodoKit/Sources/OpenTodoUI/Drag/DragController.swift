// The state of one drag space (a board, a task list): what's dragged, the
// places that take a drop and where they are, where the drag hovers, and
// the scroll views it scrolls when it nears their edges.
//
// The drag itself is the system's (SwiftUI `.draggable`, and one
// `DropDelegate` over the whole space; see DragViews.swift): it lifts the
// card on iOS after a long press (a long press that doesn't move shows the
// context menu instead), drags straight away with the mouse on macOS, and
// reports the pointer as it moves. Everything else is worked out here from
// measured geometry, by the pure functions in DropGeometry.swift.

import CoreGraphics
import Observation
import OpenTodoDomain
import SwiftUI

@MainActor @Observable
public final class DragController {
    /// The name of the coordinate space the geometry is measured in.
    public nonisolated static let space = "OpenTodo.dragSpace"

    /// What's being dragged, from the moment a drag starts in this space.
    public private(set) var item: DragItem?

    /// Where it would land now; nil when nothing under the pointer takes it.
    public private(set) var hover: DropHover?

    /// The drag is over this space.
    public private(set) var inside = false

    /// Gets what a drop comes to.
    @ObservationIgnored public var onDrop: (DropOutcome) -> Void

    /// A row lifted by its sort handle (`SortHandle`): it moves straight up
    /// and down only, drawn by the space over everything (`preview` at
    /// `frame`, moved by `dy`), and lands only in the places `allows`.
    public struct Lift {
        public var frame: CGRect
        public var dy: CGFloat
        var startY: CGFloat
        var allows: (DropSlot) -> Bool
        public var preview: AnyView
    }

    public private(set) var lift: Lift?

    /// Where the space is in the terms places are measured in: zero on
    /// macOS, its place on the screen on iOS (`dragFrame`).
    public internal(set) var origin: CGPoint = .zero

    struct SlotEntry {
        var frame: CGRect
        var kind: DropSlotKind
        var clips: [String]
        /// The view that registered it (`DropSlotModifier`'s own id).
        var owner: UUID?
    }

    struct Region {
        var frame: CGRect
        var axis: Axis
        var clips: [String]
        var scroll: (CGFloat) -> Void
    }

    @ObservationIgnored private var slots: [String: SlotEntry] = [:]
    @ObservationIgnored private var regions: [String: Region] = [:]
    @ObservationIgnored private var location: CGPoint?
    @ObservationIgnored private var scrolling: Task<Void, Never>?

    public init(onDrop: @escaping (DropOutcome) -> Void = { _ in }) {
        self.onDrop = onDrop
    }

    // MARK: The drag

    /// A drag of `item` starts.
    public func begin(_ item: DragItem) {
        self.item = item
        set(hover: nil)
    }

    /// The pointer is at `p` (in the space's coordinates).
    public func move(to p: CGPoint) {
        guard item != nil else { return }
        if !inside { inside = true }
        location = p
        rehover()
        if scrolling == nil, scrollSteps(at: p).contains(where: { $0.1 != 0 }) { startScrolling() }
    }

    /// A sort handle is pressed on the row whose place is `slotId`: `item`
    /// lifts and goes up and down with the pointer, landing only where
    /// `allows` says. The pointer is followed by how far it has moved
    /// (`moveLift(by:)`), from the row's middle: inside an iOS list row a
    /// gesture can't read the space's coordinates.
    public func beginLift(_ item: DragItem, slotId: String, preview: AnyView,
                          allows: @escaping (DropSlot) -> Bool) {
        guard let entry = slots[slotId] else { return }
        lift = Lift(frame: entry.frame, dy: 0, startY: entry.frame.midY, allows: allows, preview: preview)
        begin(item)
        move(to: CGPoint(x: entry.frame.midX, y: entry.frame.midY))
    }

    /// The pointer has moved `dy` since the handle was pressed.
    public func moveLift(by dy: CGFloat) {
        guard var l = lift else { return }
        l.dy = dy
        lift = l
        move(to: CGPoint(x: l.frame.midX, y: l.startY + dy))
    }

    /// Let go of the lifted row.
    public func dropLift() {
        guard let l = lift else { return }
        drop(at: CGPoint(x: l.frame.midX, y: l.startY + l.dy))
    }

    /// The pointer left the space.
    public func leave() {
        if inside { inside = false }
        location = nil
        set(hover: nil)
        stopScrolling()
    }

    /// Let go at `p`: hands what it comes to to `onDrop`. Whether anything
    /// took it.
    @discardableResult
    public func drop(at p: CGPoint) -> Bool {
        move(to: p)
        defer { end() }
        guard let item, let hover, let outcome = hover.outcome(for: item) else { return hover != nil }
        onDrop(outcome)
        return true
    }

    /// The drag is over, wherever it ended.
    public func end() {
        item = nil
        lift = nil
        leave()
    }

    /// Whether the task `id` is among those being dragged over the space.
    public func isDragged(_ taskId: String) -> Bool {
        guard inside, case .tasks(let d) = item else { return false }
        return d.contains(taskId)
    }

    /// Whether the section `id` is being dragged over the space.
    public func isDragged(section id: String) -> Bool {
        guard inside, case .section(let s) = item else { return false }
        return s.id == id
    }

    /// Whether the group `target` lights up as a whole (a drop that only
    /// changes group).
    public func highlights(_ target: GroupTarget) -> Bool {
        hover?.indicator == .group(target)
    }

    /// Whether a section is being dragged (task drop places stay quiet).
    public var draggingSection: Bool {
        if case .section = item { true } else { false }
    }

    // MARK: Geometry

    /// The places that take a drop, their frames cut to what their scroll
    /// views show (while a row is lifted, only those it may land in).
    public var visibleSlots: [DropSlot] {
        slots.compactMap { id, s in
            let frame = clip(s.frame, s.clips)
            let slot = DropSlot(id: id, frame: frame, kind: s.kind)
            return frame.isEmpty || lift.map({ $0.allows(slot) }) == false ? nil : slot
        }
    }

    func setSlot(_ id: String, frame: CGRect? = nil, kind: DropSlotKind? = nil, clips: [String], owner: UUID? = nil) {
        var entry = slots[id] ?? SlotEntry(frame: .zero, kind: kind ?? .taskArea(GroupDrop(.order), index: 0), clips: clips)
        if let frame { entry.frame = frame }
        if let kind { entry.kind = kind }
        entry.clips = clips
        if let owner { entry.owner = owner }
        slots[id] = entry
    }

    /// Forgets the place `id` — unless another view has taken it over since
    /// (`owner`): when a list rebuilds a row, the new row can register before
    /// the old one says it's gone, and the place would vanish with it.
    func removeSlot(_ id: String, owner: UUID? = nil) {
        if let owner, let current = slots[id]?.owner, current != owner { return }
        slots[id] = nil
    }

    /// The places inside the scroll view `region` that it shows now.
    public func visibleSlotIds(in region: String) -> Set<String> {
        Set(slots.compactMap { id, s in
            s.clips.contains(region) && !clip(s.frame, s.clips).isEmpty ? id : nil
        })
    }

    func setRegion(_ id: String, frame: CGRect, axis: Axis, clips: [String], scroll: @escaping (CGFloat) -> Void) {
        regions[id] = Region(frame: frame, axis: axis, clips: clips, scroll: scroll)
    }

    func removeRegion(_ id: String) { regions[id] = nil }

    private func clip(_ frame: CGRect, _ clips: [String]) -> CGRect {
        clips.reduce(frame) { f, id in regions[id].map { f.intersection($0.frame) } ?? f }
    }

    private func set(hover new: DropHover?) {
        if new != hover { hover = new }
    }

    private func rehover() {
        guard let item, let location else { return set(hover: nil) }
        set(hover: resolveDrop(item, at: location, in: visibleSlots))
    }

    // MARK: Scrolling at the edges

    private func scrollSteps(at p: CGPoint) -> [(String, CGFloat)] {
        regions.map { id, r in
            let step = edgeScrollStep(p, in: clip(r.frame, r.clips), axis: r.axis)
            // A row lifted by its handle near an edge starts there: only
            // scroll once it's been moved toward that edge.
            if let lift, step != 0, !(abs(lift.dy) > 8 && (lift.dy > 0) == (step > 0)) { return (id, 0) }
            return (id, step)
        }
    }

    private func startScrolling() {
        scrolling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.tick() else { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            self?.scrolling = nil
        }
    }

    private func stopScrolling() {
        scrolling?.cancel()
        scrolling = nil
    }

    /// One frame of scrolling; false once nothing needs to.
    private func tick() -> Bool {
        guard let location, item != nil else { return false }
        var any = false
        for (id, step) in scrollSteps(at: location) where step != 0 {
            regions[id]?.scroll(step)
            any = true
        }
        rehover()
        return any
    }
}
