// The view side of dragging: a space that takes drops (`dragSpace`), the
// places in it that take them (`dropSlot`), the things that can be dragged
// (`taskDragSource`, `sectionDragSource`), scroll views that follow a drag
// to their edges (`dragAutoScroll`), and the dragged copy
// (`DragStackPreview`). The board and the task list use the same pieces;
// each says where its own drops land.
//
//     let drag = DragController { outcome in … }   // @State
//     ScrollView {
//         ForEach(rows) { row in
//             Row(row)
//                 .taskDragSource(row.task, picked: picked) { RowPreview(row) }
//                 .dropSlot("row-\(row.id)", .taskRow(group, index: i))
//         }
//     }
//     .dragAutoScroll("list", axis: .vertical)
//     .dragSpace(drag)

import OpenTodoDomain
import SwiftUI
import UniformTypeIdentifiers

/// What the system carries for a drag that starts here: the titles, as
/// text, so a task dropped on another app arrives as its title. What's
/// dragged within the app is in the `DragController`.
nonisolated struct DragToken: Transferable {
    var text: String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.text)
    }
}

/// The scroll views a place is inside, innermost last: what it's cut to.
extension EnvironmentValues {
    @Entry var dragClips: [String] = []
}

extension View {
    /// Makes this the space drags happen in: measures the places that take
    /// drops, takes the drop, and draws the insertion line.
    public func dragSpace(_ controller: DragController) -> some View {
        modifier(DragSpace(controller: controller))
    }

    /// A place in the drag space that takes a drop (`kind` says what and
    /// where). `outset` grows it past the view, into the spacing around it,
    /// so there's no dead gap between rows. `id` must be unique in the space.
    public func dropSlot(_ id: String, _ kind: DropSlotKind, outset: EdgeInsets = EdgeInsets()) -> some View {
        modifier(DropSlotModifier(id: id, kind: kind, outset: outset))
    }

    /// Lets `task` be dragged — with `picked` (in the order shown) when it
    /// is one of them. `preview` is the dragged copy (one card; a stack
    /// with the count is drawn around it when several go).
    public func taskDragSource<Preview: View>(
        _ task: TodoTask,
        picked: [TodoTask] = [],
        isEnabled: Bool = true,
        @ViewBuilder preview: @escaping () -> Preview
    ) -> some View {
        let dragged = DraggedTasks(task, picked: picked)
        return modifier(DragSource(
            item: .tasks(dragged),
            text: dragged.all.map(\.title).joined(separator: "\n"),
            count: dragged.count,
            isEnabled: isEnabled,
            preview: preview
        ))
    }

    /// Lets a list's `section` be dragged by this view (its header, a board
    /// column's top).
    public func sectionDragSource<Preview: View>(
        _ section: ListSection,
        isEnabled: Bool = true,
        @ViewBuilder preview: @escaping () -> Preview
    ) -> some View {
        modifier(DragSource(item: .section(section), text: section.name, count: 1, isEnabled: isEnabled, preview: preview))
    }

    /// Scrolls this scroll view along `axis` while a drag nears its edges,
    /// and cuts the places inside it to what it shows. `id` must be unique
    /// in the space.
    public func dragAutoScroll(_ id: String, axis: Axis) -> some View {
        modifier(DragAutoScroll(id: id, axis: axis))
    }

    /// The same for a `List`, which a `ScrollPosition` doesn't move: it
    /// scrolls a row at a time (`ScrollViewReader`). `rows` are the ids of
    /// its rows in order, each with a place whose id is `row-<id>`.
    public func dragAutoScroll(_ id: String, rows: [String]) -> some View {
        modifier(ListAutoScroll(id: id, rows: rows))
    }
}

// MARK: - The space

private struct DragSpace: ViewModifier {
    let controller: DragController

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                DropIndicatorView(hover: controller.hover)
            }
            .coordinateSpace(.named(DragController.space))
            .onDrop(of: [.text], delegate: SpaceDropDelegate(controller: controller))
            .environment(controller)
    }
}

private struct SpaceDropDelegate: DropDelegate {
    let controller: DragController

    func validateDrop(info: DropInfo) -> Bool { controller.item != nil }

    func dropEntered(info: DropInfo) { controller.move(to: info.location) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        controller.move(to: info.location)
        return DropProposal(operation: controller.hover == nil ? .forbidden : .move)
    }

    func dropExited(info: DropInfo) { controller.leave() }

    func performDrop(info: DropInfo) -> Bool { controller.drop(at: info.location) }
}

/// The insertion line (with a ring at its start, as AppKit draws it) or
/// the lit-up area; group highlights are drawn by the groups themselves.
private struct DropIndicatorView: View {
    let hover: DropHover?

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch hover?.indicator {
            case let .line(a, b)?:
                let horizontal = abs(b.x - a.x) >= abs(b.y - a.y)
                let ring: CGFloat = 7
                Path { p in
                    // The line starts past the ring.
                    p.move(to: horizontal ? CGPoint(x: a.x + ring, y: a.y) : CGPoint(x: a.x, y: a.y + ring))
                    p.addLine(to: b)
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: ring, height: ring)
                    .offset(x: horizontal ? a.x : a.x - ring / 2, y: horizontal ? a.y - ring / 2 : a.y)
            case let .area(rect)?:
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .animation(.snappy(duration: 0.15), value: hover?.indicator)
        .accessibilityHidden(true)
    }
}

// MARK: - Places and sources

private struct DropSlotModifier: ViewModifier {
    let id: String
    let kind: DropSlotKind
    let outset: EdgeInsets
    @Environment(DragController.self) private var controller: DragController?
    @Environment(\.dragClips) private var clips

    func body(content: Content) -> some View {
        content
            // Measured on a view behind it, the same size: on the list's
            // rows (macOS), `onGeometryChange` on the row itself, together
            // with the row's `.draggable`, kept a click from selecting the
            // row — the task never opened (docs/apple.md §10).
            .background {
                Color.clear.onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(DragController.space))
                } action: { frame in
                    let f = CGRect(
                        x: frame.minX - outset.leading,
                        y: frame.minY - outset.top,
                        width: frame.width + outset.leading + outset.trailing,
                        height: frame.height + outset.top + outset.bottom
                    )
                    controller?.setSlot(id, frame: f, kind: kind, clips: clips)
                }
            }
            .onChange(of: kind, initial: true) { _, kind in
                controller?.setSlot(id, kind: kind, clips: clips)
            }
            .onDisappear { controller?.removeSlot(id) }
    }
}

private struct DragSource<Preview: View>: ViewModifier {
    let item: DragItem
    let text: String
    let count: Int
    let isEnabled: Bool
    let preview: () -> Preview
    @Environment(DragController.self) private var controller: DragController?

    func body(content: Content) -> some View {
        if isEnabled, let controller {
            content
                .draggable(token(controller)) {
                    DragStackPreview(count: count, content: preview)
                }
                .modifier(DragEnds(controller: controller))
        } else {
            content
        }
    }

    /// Called by the system as the drag starts (the payload is an
    /// autoclosure): that's when the controller learns what's dragged.
    private func token(_ controller: DragController) -> DragToken {
        controller.begin(item)
        return DragToken(text: text)
    }
}

/// Where the system says when a drag ended (iOS 27, macOS 26), the
/// controller hears it even if it ended outside the space; before that,
/// leaving the space or the next drag clears it.
private struct DragEnds: ViewModifier {
    let controller: DragController

    func body(content: Content) -> some View {
        if #available(iOS 27, macOS 26, *) {
            content.onDragSessionUpdated { session in
                if case .ended = session.phase { controller.end() }
            }
        } else {
            content
        }
    }
}

// MARK: - Scrolling

private final class ScrollState {
    var offset: CGPoint = .zero
    var content: CGSize = .zero
    var viewport: CGSize = .zero
}

private struct DragAutoScroll: ViewModifier {
    let id: String
    let axis: Axis
    @State private var position = ScrollPosition()
    @State private var state = ScrollState()
    @Environment(DragController.self) private var controller: DragController?
    @Environment(\.dragClips) private var clips

    func body(content: Content) -> some View {
        let position = $position, state = state, axis = axis
        let scroll: (CGFloat) -> Void = { step in
            let to: CGFloat
            if axis == .vertical {
                to = clampedScrollOffset(state.offset.y, by: step, content: state.content.height, viewport: state.viewport.height)
                if to != state.offset.y { position.wrappedValue.scrollTo(y: to) }
            } else {
                to = clampedScrollOffset(state.offset.x, by: step, content: state.content.width, viewport: state.viewport.width)
                if to != state.offset.x { position.wrappedValue.scrollTo(x: to) }
            }
        }
        content
            .environment(\.dragClips, clips + [id])
            .scrollPosition(position)
            .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, g in
                state.offset = g.contentOffset
                state.content = g.contentSize
                state.viewport = g.containerSize
            }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(DragController.space))
            } action: { frame in
                controller?.setRegion(id, frame: frame, axis: axis, clips: clips, scroll: scroll)
            }
            .onDisappear { controller?.removeRegion(id) }
    }
}

/// Scrolls a `List` a row at a time while a drag is near its edges.
private struct ListAutoScroll: ViewModifier {
    let id: String
    let rows: [String]
    @State private var travel = Travel()
    @Environment(DragController.self) private var controller: DragController?
    @Environment(\.dragClips) private var clips

    /// How far the edge has asked to scroll since the last row.
    private final class Travel {
        var points: CGFloat = 0
    }

    /// About a row's height.
    private static let row: CGFloat = 32

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .environment(\.dragClips, clips + [id])
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(DragController.space))
                } action: { frame in
                    controller?.setRegion(id, frame: frame, axis: .vertical, clips: clips) { step in
                        scroll(step, proxy)
                    }
                }
                .onDisappear { controller?.removeRegion(id) }
        }
    }

    private func scroll(_ step: CGFloat, _ proxy: ScrollViewProxy) {
        guard let controller else { return }
        if (travel.points > 0) != (step > 0) { travel.points = 0 }
        travel.points += step
        guard abs(travel.points) >= Self.row else { return }
        travel.points = 0
        let shown = controller.visibleSlotIds(in: id)
        let visible = rows.indices.filter { shown.contains("row-\(rows[$0])") }
        guard let first = visible.first, let last = visible.last else { return }
        if step > 0, last + 1 < rows.count {
            proxy.scrollTo(rows[last + 1], anchor: .bottom)
        } else if step < 0, first > 0 {
            proxy.scrollTo(rows[first - 1], anchor: .top)
        }
    }
}

// MARK: - The dragged copy

/// The dragged copy of a card or row: lifted, and when `count` things go
/// together, a card behind it and how many.
public struct DragStackPreview<Content: View>: View {
    @Environment(\.uiScale) private var s
    let count: Int
    let content: () -> Content

    public init(count: Int, @ViewBuilder content: @escaping () -> Content) {
        self.count = count
        self.content = content
    }

    public var body: some View {
        content()
            .background {
                if count > 1 {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.background.secondary)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        .offset(x: 6, y: 6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    Text(count, format: .number)
                        .uiFont(.caption, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7 * s)
                        .frame(minWidth: 22 * s, minHeight: 22 * s)
                        .background(Capsule().fill(Color.accentColor))
                        .offset(x: 8, y: -8)
                        .accessibilityLabel("\(count) 个任务")
                }
            }
            .padding(10 * s)
    }
}
