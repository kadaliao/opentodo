// Rows one under another that are put in order by a handle (≡) at each
// row's end: the row follows the pointer straight up and down only (never
// sideways), kept about within the stack, the rows it passes slide out of
// its way, and letting go hands the new place to `onMove`. Until the rows
// come back in the new order, the stack keeps showing it (so nothing jumps
// back for a moment). The detail's subtasks (`ChecklistStack`) and the
// four quadrants use it.
//
//     ReorderStack(tasks, handles: .onHover) { task in
//         MatrixTaskRow(task: task, …)
//     } onMove: { task, position in … moving(tasks, task.id, to: position) … }

import SwiftUI

/// When a `ReorderStack`'s handles show.
enum ReorderHandles { case onHover, always, hidden }

struct ReorderStack<Item: Identifiable, Row: View>: View where Item.ID == String {
    typealias Handles = ReorderHandles

    let items: [Item]
    var handles: Handles = .onHover
    /// Lines between rows, starting this far in (nil: none).
    var dividerInset: CGFloat?
    @ViewBuilder let row: (Item) -> Row
    let onMove: (Item, Int) -> Void

    @Environment(\.uiScale) private var s
    @State private var heights: [String: CGFloat] = [:]
    @State private var dragging: String?
    @State private var dy: CGFloat = 0
    @State private var pending: [String]?
    @State private var hovered: String?

    init(_ items: [Item], handles: Handles = .onHover, dividerInset: CGFloat? = nil,
         @ViewBuilder row: @escaping (Item) -> Row, onMove: @escaping (Item, Int) -> Void) {
        self.items = items
        self.handles = handles
        self.dividerInset = dividerInset
        self.row = row
        self.onMove = onMove
    }

    var body: some View {
        let shown = ordered
        let drag = dragState(shown)
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                let lifted = item.id == dragging
                VStack(spacing: 0) {
                    if i > 0, let inset = dividerInset {
                        Divider().padding(.leading, inset)
                            .opacity(lifted || drag.map { $0.shifts(i) != 0 } == true ? 0 : 1)
                    }
                    HStack(spacing: 4 * s) {
                        row(item)
                        if handles != .hidden {
                            handle(item, shown)
                                .opacity(handles == .always || hovered == item.id || lifted ? 1 : 0)
                        }
                    }
                }
                .background {
                    if lifted {
                        RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    }
                }
                .onHover { over in
                    if over { hovered = item.id } else if hovered == item.id { hovered = nil }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[item.id] = $0 }
                .offset(y: lifted ? dy : drag?.shifts(i) ?? 0)
                .zIndex(lifted ? 1 : 0)
                .animation(lifted ? nil : .snappy(duration: 0.18), value: drag?.position)
            }
        }
        .onChange(of: items.map(\.id)) { pending = nil }
        .preference(key: ReorderingKey.self, value: dragging != nil)
    }

    private var ordered: [Item] {
        guard let pending else { return items }
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let known = pending.compactMap { byId[$0] }
        return known.count == items.count ? known : items
    }

    private func dragState(_ shown: [Item]) -> StackDrag? {
        guard let dragging, let from = shown.firstIndex(where: { $0.id == dragging }) else { return nil }
        return StackDrag(from: from, dy: dy, heights: shown.map { heights[$0.id] ?? 0 })
    }

    private func handle(_ item: Item, _ shown: [Item]) -> some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.secondary)
            #if os(macOS)
            .frame(width: 22 * s, height: 22 * s)
            #else
            .frame(width: 40 * s, height: 36 * s)
            #endif
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if dragging == nil { dragging = item.id }
                        guard let from = shown.firstIndex(where: { $0.id == item.id }) else { return }
                        dy = StackDrag.clamp(value.translation.height, from: from,
                                             heights: shown.map { heights[$0.id] ?? 0 })
                    }
                    .onEnded { _ in drop(item, shown) }
            )
            .help("拖动排序")
            .accessibilityLabel("拖动排序")
    }

    private func drop(_ item: Item, _ shown: [Item]) {
        defer {
            dragging = nil
            dy = 0
        }
        guard let state = dragState(shown) else { return }
        let p = state.position
        guard p != state.from else { return }
        var ids = shown.map(\.id)
        ids.move(fromOffsets: [state.from], toOffset: p > state.from ? p + 1 : p)
        pending = ids
        onMove(item, p)
    }
}

/// Whether a row of a stack inside is being dragged by its handle: the
/// scroll view around it (`reorderScrollLock()`) stops scrolling with the
/// finger meanwhile, or on iOS the rows would move under it.
struct ReorderingKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// Put on the `Form`, `List` or `ScrollView` around a `ReorderStack`.
    func reorderScrollLock() -> some View { modifier(ReorderScrollLock()) }
}

private struct ReorderScrollLock: ViewModifier {
    @State private var locked = false

    func body(content: Content) -> some View {
        content
            .scrollDisabled(locked)
            .onPreferenceChange(ReorderingKey.self) { locked = $0 }
    }
}
