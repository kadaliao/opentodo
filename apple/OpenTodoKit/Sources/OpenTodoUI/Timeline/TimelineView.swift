// The timeline (时间线) of a view, as a self-contained component: its dated
// tasks as bars along the days, a lane per section of a list (per group
// elsewhere), and the undated ones beside it (无日期) to drag on. Ported
// from `app/lib/ui/timeline_view.dart`; laid out like Calendar.
//
// The component takes values and gives back what the person did; it never
// touches the database. The caller:
//
//     TimelineView(
//         timeline: buildViewTimeline(view, tasks, now: now, lists: …, filters: …,
//                                     sectionsByList: …, grouping: …, sort: …,
//                                     showDone: prefs.showDone),
//         view: view, now: now, selectedTaskId: openTaskId,
//         prefs: $timelinePrefs,           // LocalSettings.timelinePrefs
//         selection: model.selection.picked,
//         onTap: { id, modifiers, order in   // a click: open, or ⌘ / Shift pick
//             if let open = model.selection.tap(id, modifiers: modifiers, order: order,
//                                               current: model.selectedTaskId) { … open it … }
//         },
//         onSetDone: { task, done in repo.setCompleted(task.id, done) },
//         onEdit: { edit in … see TimelineEdit for the TaskRepo call of each … },
//         onNewTask: { day, target in
//             let n = laneNewTask(view, target, now.day, filterRules)
//             … the new-task dialog on `day` with n.listId, n.sectionId, n.tags, n.priority …
//         }
//     ) { task in
//         … the task's menu: Buttons (right-click on a Mac, a long press
//           without moving on a phone) …
//     }
//
// Horizontal scrolling is a real `ScrollView` over a strip ten years
// either way (so trackpads, wheels and momentum feel native); only what's
// near the screen is built. Dragging is the component's own, so bars move
// between lanes and the 无日期 tray with one gesture.

import OpenTodoData
import OpenTodoDomain
import SwiftUI

public struct TimelineView<TaskMenu: View>: View {
    let timeline: Timeline
    let view: ViewRef
    let now: LocalDateTime
    let selectedTaskId: String?
    @Binding var prefs: TimelinePrefs
    /// The picked tasks (多选), which drag together.
    let selection: TaskSelection
    /// A click or tap on a task: its id, the keys held and the tasks in the
    /// order shown (for Shift); the caller picks or opens (`tapTask`).
    let onTap: (String, TapModifiers, [String]) -> Void
    let onSetDone: (TodoTask, Bool) -> Void
    let onEdit: (TimelineEdit) -> Void
    let onNewTask: (Day, GroupTarget?) -> Void
    let taskMenu: (TodoTask) -> TaskMenu
    /// Debug scenes only: a drag to show as if under way, for screenshots.
    var staged: TimelineStagedDrag?

    @State private var origin: Day
    @State private var hPos: ScrollPosition
    @State private var vPos = ScrollPosition(y: 0)
    @State private var scrollX: Double
    @State private var scrollY: Double = 0
    @State private var rootWidth: Double = 1000
    /// The canvas (day header and lanes) in the component's space.
    @State private var canvasFrame: CGRect = .zero
    @State private var trayFrame: CGRect = .zero
    /// Lanes folded, by `TimelineLane.id`.
    @State private var collapsed: Set<String> = []
    @State private var drag: TimelineDrag?
    /// The lane and day under the mouse, where a click adds a task.
    @State private var hover: TimelineHover?
    /// The task whose menu shows after a long press (touch screens).
    @State private var menu: TimelineMenu?

    public init(
        timeline: Timeline,
        view: ViewRef,
        now: LocalDateTime,
        selectedTaskId: String? = nil,
        prefs: Binding<TimelinePrefs>,
        selection: TaskSelection,
        onTap: @escaping (String, TapModifiers, [String]) -> Void,
        onSetDone: @escaping (TodoTask, Bool) -> Void,
        onEdit: @escaping (TimelineEdit) -> Void,
        onNewTask: @escaping (Day, GroupTarget?) -> Void,
        @ViewBuilder taskMenu: @escaping (TodoTask) -> TaskMenu
    ) {
        self.timeline = timeline
        self.view = view
        self.now = now
        self.selectedTaskId = selectedTaskId
        _prefs = prefs
        self.selection = selection
        self.onTap = onTap
        self.onSetDone = onSetDone
        self.onEdit = onEdit
        self.onNewTask = onNewTask
        self.taskMenu = taskMenu
        let origin = TimelineGeometry.origin(today: now.day)
        let x = Self.homeOffset(origin: origin, timeline: timeline, view: view, today: now.day, scale: prefs.wrappedValue.scale)
        _origin = State(initialValue: origin)
        _hPos = State(initialValue: ScrollPosition(x: x))
        _scrollX = State(initialValue: x)
    }

    // MARK: Derived

    private var today: Day { now.day }
    private var scale: TimelineScale { prefs.scale }
    private var touch: Bool { TimelineStyle.touch }
    private var narrow: Bool { rootWidth < 640 }
    /// A year at the narrowest scale: a jump from further than this to the
    /// strip's start is a layout pass, not someone scrolling.
    private static var farFromStart: Double { 365 * TimelineMetrics.dayWidth(.month) }
    private var trayOpen: Bool { timeline.takesUndated && (prefs.trayOpen ?? !narrow) }

    private var geometry: TimelineGeometry {
        TimelineGeometry(origin: origin, scale: scale, scrollX: scrollX, width: canvasFrame.width)
    }

    private var rows: [[[TimelineBar]]] {
        timeline.lanes.map { packRows($0.bars, minDays: scale.minDays) }
    }

    private var lanesHeight: Double { max(canvasFrame.height - TimelineMetrics.headerHeight, 0) }

    private func layout(_ rows: [[[TimelineBar]]]) -> TimelineLaneLayout {
        let titled = timeline.titled
        return TimelineLaneLayout(
            rows: rows.map(\.count),
            titled: titled,
            collapsed: timeline.lanes.map { collapsed.contains($0.id) },
            minHeight: lanesHeight - TimelineMetrics.bottomPadding - (titled ? TimelineMetrics.laneHeaderHeight : 0)
        )
    }

    /// Ids in the order shown, for Shift-clicks: the undated ones, then lane
    /// by lane.
    private var order: [TodoTask] {
        timeline.undatedTasks + timeline.lanes.flatMap { $0.bars.map(\.task) }
    }

    /// The picked tasks, which are dragged together.
    private var picked: [TodoTask] {
        selection.active ? order.filter { selection.contains($0.id) && isOpen($0) } : []
    }

    private func isSelected(_ id: String) -> Bool {
        selection.active ? selection.contains(id) : selectedTaskId == id
    }

    /// Content x of the screen's left edge, and how wide the band built
    /// around the screen is: half a screen each side, so a frame of
    /// scrolling never shows an edge.
    private var window: (minX: Double, width: Double) {
        let g = geometry
        let w = max(g.width, 320)
        let minX = max(scrollX - w / 2, 0)
        return (minX, min(2 * w, g.contentWidth - minX))
    }

    private static func homeOffset(origin: Day, timeline: Timeline, view: ViewRef, today: Day, scale: TimelineScale) -> Double {
        let overdue = isDateView(view) ? TimelineDragMath.earliestOverdue(timeline, today: today) : nil
        let left = TimelineDragMath.homeLeftDay(today: today, scale: scale, earliestOverdue: overdue)
        return Double(origin.days(to: left)) * TimelineMetrics.dayWidth(scale)
    }

    // MARK: Body

    public var body: some View {
        let rows = self.rows
        let layout = layout(rows)
        let target = dropTarget(layout: layout)
        VStack(spacing: 0) {
            toolbar
            Divider()
            // Narrow: the tray under the days; wide: beside them. One
            // layout that changes direction, so the canvas stays the same
            // view when the width crosses the line: in two stacks it was
            // built afresh and its scroll view started at the strip's left
            // end, ten years back.
            let stack = narrow ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            stack {
                if trayOpen && !narrow {
                    tray(target: target).frame(width: 220)
                    Divider()
                }
                canvas(rows: rows, layout: layout, target: target)
                    // The days run on under the home indicator.
                    .ignoresSafeArea(.container, edges: narrow && !trayOpen ? .bottom : [])
                if trayOpen && narrow {
                    Divider()
                    tray(target: target).frame(height: 132)
                }
            }
        }
        .coordinateSpace(.named(timelineSpace))
        .overlay(alignment: .topLeading) { dragPreview.allowsHitTesting(false) }
        .onGeometryChange(for: Double.self) { $0.size.width } action: { rootWidth = $0 }
        .onChange(of: canvasFrame) { stage() }
        .task(id: drag != nil) { await autoScroll() }
        .onChange(of: prefs.scale) { old, new in
            let x = TimelineGeometry.offsetAfterScaleChange(
                from: old, to: new, scrollX: scrollX, origin: origin, home: today
            )
            scrollX = x
            hPos.scrollTo(x: x)
        }
        #if os(iOS)
        .popover(
            item: $menu,
            attachmentAnchor: .rect(.rect(menu?.rect ?? .zero)),
            arrowEdge: .bottom
        ) { m in
            VStack(alignment: .leading, spacing: 0) { taskMenu(m.task) }
                .buttonStyle(TimelineMenuButtonStyle())
                .padding(.vertical, 6)
                .frame(minWidth: 220, alignment: .leading)
                .simultaneousGesture(TapGesture().onEnded { menu = nil })
                .presentationCompactAdaptation(.popover)
        }
        #endif
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(timelineMonthLabel(geometry.leftDay))
                .font(narrow ? .headline : .title2.weight(.semibold))
                .lineLimit(1)
                .contentTransition(.numericText())
            Spacer(minLength: 8)
            if timeline.takesUndated {
                Button {
                    prefs.trayOpen = !trayOpen
                } label: {
                    Label("无日期 \(timeline.undatedTasks.count)", systemImage: "tray")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .tint(trayOpen ? Color.accentColor : Color.secondary)
                .controlSize(narrow ? .small : .regular)
                .accessibilityAddTraits(trayOpen ? .isSelected : [])
            }
            if !narrow {
                Picker("缩放", selection: $prefs.scale) {
                    ForEach(TimelineScale.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                #if os(macOS)
                ControlGroup {
                    Button { page(-1) } label: { Image(systemName: "chevron.left") }
                        .help("往前")
                    Button("今天") { goHome() }
                    Button { page(1) } label: { Image(systemName: "chevron.right") }
                        .help("往后")
                }
                .fixedSize()
                #else
                HStack(spacing: 2) {
                    Button { page(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("往前")
                    Button("今天") { goHome() }
                    Button { page(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("往后")
                }
                .buttonStyle(.bordered)
                #endif
            } else {
                Button("今天") { goHome() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Menu {
                Picker("缩放", selection: $prefs.scale) {
                    ForEach(TimelineScale.allCases, id: \.self) { Text("按\($0.label)").tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("显示已完成", isOn: $prefs.showDone)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("时间线选项")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, narrow ? 6 : 10)
    }

    private func goHome() {
        let x = Self.homeOffset(origin: origin, timeline: timeline, view: view, today: today, scale: scale)
        withAnimation(.smooth(duration: 0.3)) { hPos.scrollTo(x: x) }
    }

    private func page(_ direction: Int) {
        let dw = geometry.dayWidth
        let days = max(Int(canvasFrame.width / dw) - 1, 1)
        let x = ((scrollX / dw).rounded() + Double(direction * days)) * dw
        withAnimation(.smooth(duration: 0.3)) { hPos.scrollTo(x: min(max(x, 0), geometry.contentWidth - canvasFrame.width)) }
    }

    // MARK: Canvas

    private func canvas(rows: [[[TimelineBar]]], layout: TimelineLaneLayout, target: TimelineDropTarget?) -> some View {
        let g = geometry
        let win = window
        let dropDays: TimelineDropDays? = if case .lane(_, let d)? = target { d } else { nil }
        let nowX = g.contentX(today) + (scale == .month ? g.dayWidth / 2 : g.dayWidth * Double(now.minuteOfDay) / Double(minutesPerDay))
        let height = canvasFrame.height
        // The canvas takes the space it's offered, measured on an empty
        // view: measuring the scroll view itself fed its content's height
        // back into its size, and on a phone (which lets it run on under
        // the home indicator) it grew to the whole screen and pushed the
        // header up under the navigation bar.
        return Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(timelineSpace)) } action: { canvasFrame = $0 }
            .overlay(alignment: .topLeading) {
                // Only once the canvas has its width: a scroll view laid
                // out at width 0 first lost its place when it got the real
                // width, and the strip opened at its left end, ten years
                // back (on a Mac the timeline is first laid out before the
                // window's columns settle).
                if canvasFrame.width > 0 {
                    canvasScroll(rows: rows, layout: layout, target: target, height: height, g: g, win: win, dropDays: dropDays, nowX: nowX)
                }
            }
            .onChange(of: canvasFrame.width > 0) { _, has in
                // Built again after being gone: back where it was.
                if has { hPos = ScrollPosition(x: scrollX) }
            }
            .background(.background)
            .clipped()
    }

    private func canvasScroll(
        rows: [[[TimelineBar]]], layout: TimelineLaneLayout, target: TimelineDropTarget?, height: Double,
        g: TimelineGeometry, win: (minX: Double, width: Double), dropDays: TimelineDropDays?, nowX: Double
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                TimelineGrid(geometry: g, minX: win.minX)
                    .frame(width: win.width, height: max(height - TimelineMetrics.headerHeight, 0))
                    .offset(x: win.minX, y: TimelineMetrics.headerHeight)
                    .allowsHitTesting(false)
                VStack(spacing: 0) {
                    TimelineDayHeader(geometry: g, minX: win.minX, today: today, drop: dropDays)
                        .frame(width: win.width, height: TimelineMetrics.headerHeight)
                        .offset(x: win.minX)
                        .frame(width: g.contentWidth, height: TimelineMetrics.headerHeight, alignment: .leading)
                        #if os(macOS)
                        .contentShape(Rectangle())
                        .gesture(headerDrag)
                        #endif
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(Array(timeline.lanes.enumerated()), id: \.element.id) { i, lane in
                                laneView(i, lane: lane, rows: rows[i], frame: layout.lanes[i], target: target)
                            }
                        }
                        .frame(width: g.contentWidth, alignment: .topLeading)
                        .padding(.bottom, TimelineMetrics.bottomPadding)
                    }
                    .scrollPosition($vPos)
                    .onScrollGeometryChange(for: Double.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, y in
                        scrollY = y
                    }
                    .scrollDisabled(touch && drag != nil)
                    .frame(width: g.contentWidth, height: max(height - TimelineMetrics.headerHeight, 0))
                }
                if nowX >= win.minX && nowX <= win.minX + win.width {
                    TimelineNowLine()
                        .frame(width: 9, height: max(height - TimelineMetrics.headerHeight + 4, 0))
                        .offset(x: nowX - 4.5, y: TimelineMetrics.headerHeight - 4)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: g.contentWidth, height: height, alignment: .topLeading)
        }
        .scrollPosition($hPos)
        // The content x at the canvas's left edge. In a split view the strip
        // runs on under the sidebar, inset by it; `scrollTo(x:)` counts
        // from the inset, so this does too.
        .onScrollGeometryChange(for: Double.self, of: { $0.contentOffset.x + $0.contentInsets.leading }) { _, x in
            // While the window's columns settle (the canvas's width, the
            // sidebar's inset) the scroll view lays out again and now and
            // then lands back at the strip's left end, ten years back.
            // Nobody gets there in one step: put it back.
            if x <= 0 && scrollX > Self.farFromStart {
                let back = scrollX
                DispatchQueue.main.async { hPos.scrollTo(x: back) }
                return
            }
            scrollX = x
        }
        .scrollDisabled(touch && drag != nil)
        .frame(width: canvasFrame.width, height: height)
    }

    /// A mouse dragging the dates scrolls them (a trackpad or wheel scrolls
    /// anyway; on a touch screen the header scrolls with the finger).
    private var headerDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if headerDragOrigin == nil { headerDragOrigin = scrollX }
                hPos.scrollTo(x: clampX((headerDragOrigin ?? scrollX) - v.translation.width))
            }
            .onEnded { _ in headerDragOrigin = nil }
    }

    @State private var headerDragOrigin: Double?

    private func clampX(_ x: Double) -> Double {
        min(max(x, 0), max(geometry.contentWidth - canvasFrame.width, 0))
    }

    // MARK: Lanes

    @ViewBuilder
    private func laneView(_ i: Int, lane: TimelineLane, rows: [[TimelineBar]], frame: TimelineLaneLayout.Lane, target: TimelineDropTarget?) -> some View {
        let g = geometry
        let win = window
        VStack(spacing: 0) {
            if frame.header > 0 {
                laneHeader(lane, folded: collapsed.contains(lane.id), win: win)
                    .frame(width: g.contentWidth, height: frame.header, alignment: .leading)
            }
            if frame.body > 0 {
                laneBody(i, lane: lane, rows: rows, height: frame.body, target: target)
                    .frame(width: g.contentWidth, height: frame.body, alignment: .topLeading)
            }
        }
    }

    private func laneHeader(_ lane: TimelineLane, folded: Bool, win: (minX: Double, width: Double)) -> some View {
        let count = lane.bars.count { !$0.done }
        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(.background.secondary)
                .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
                .frame(width: win.width)
                .offset(x: win.minX)
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(folded ? -90 : 0))
                Text(lane.title ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .fixedSize()
            // Stays at the left edge of the screen.
            .visualEffect { content, proxy in
                content.offset(x: -proxy.frame(in: .scrollView(axis: .horizontal)).minX)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) {
                if collapsed.remove(lane.id) == nil { collapsed.insert(lane.id) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(folded ? "展开" : "折叠")
    }

    @ViewBuilder
    private func laneBody(_ i: Int, lane: TimelineLane, rows: [[TimelineBar]], height: Double, target: TimelineDropTarget?) -> some View {
        let g = geometry
        let win = window
        let from = g.day(atContentX: win.minX) - scale.minDays
        let to = g.day(atContentX: win.minX + win.width)
        let dragged = Set(draggedTasks.map(\.id))
        ZStack(alignment: .topLeading) {
            // Clicks on empty days add a task there; the mouse shows where.
            Color.clear
                .frame(width: win.width, height: height)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { p in
                    let day = g.day(atContentX: win.minX + p.x)
                    if dateViewShows(view, day, today) { onNewTask(day, lane.target) }
                }
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let p):
                        let day = g.day(atContentX: win.minX + p.x)
                        let h = dateViewShows(view, day, today) ? TimelineHover(lane: i, day: day) : nil
                        if h != hover { hover = h }
                    case .ended:
                        if hover?.lane == i { hover = nil }
                    }
                }
                .offset(x: win.minX)

            if let h = hover, h.lane == i, drag == nil {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.accentColor.opacity(0.06))
                    .overlay(alignment: .topLeading) {
                        if g.dayWidth >= 30 {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(6)
                        }
                    }
                    .frame(width: g.dayWidth, height: height)
                    .offset(x: g.contentX(h.day))
                    .allowsHitTesting(false)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { row, bars in
                ForEach(bars, id: \.task.id) { b in
                    if b.overlaps(from, to) || dragged.contains(b.task.id) {
                        barView(b, lane: i, row: row)
                    }
                }
            }

            if case .lane(i, let d)? = target {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
                    .strokeBorder(Color.accentColor, lineWidth: 1)
                    .frame(width: Double(d.days) * g.dayWidth, height: height)
                    .offset(x: g.contentX(d.start))
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Bars

    @ViewBuilder
    private func barView(_ b: TimelineBar, lane: Int, row: Int) -> some View {
        let g = geometry
        let resizing: (start: Bool, day: Day)? = if case .resize(let rb, let start, _, _)? = drag?.kind, rb.task.id == b.task.id {
            (start, resizeDay ?? (start ? b.start : b.last))
        } else { nil }
        let first = resizing.map { $0.start ? $0.day : b.start } ?? b.start
        let last = resizing.map { $0.start ? b.last : $0.day } ?? b.last
        let days = first.days(to: last) + 1
        let left = g.contentX(first) + TimelineMetrics.barInset
        let width = Double(days) * g.dayWidth - 2 * TimelineMetrics.barInset
        let top = TimelineLaneLayout.barTop(row: row)
        let open = !b.done
        let inside = touch ? min(16, width / 3) : 5
        let outside = open ? (touch ? 12.0 : 3.0) : 0
        let isDragged = draggedTasks.contains { $0.id == b.task.id } && isMoving
        let viewportLeft = left - scrollX

        // The bar, with room either side for its edges.
        TimelineBarFace(
            task: b.task,
            width: max(width, 4),
            selected: isSelected(b.task.id),
            overdue: isOverdue(b.task, now),
            shift: TimelineDragMath.stickyTitleOffset(barLeft: viewportLeft, barWidth: width),
            onToggle: { onSetDone(b.task, b.done ? false : true) }
        )
        .opacity(isDragged ? 0.3 : 1)
        .padding(.horizontal, outside)
        .contentShape(Rectangle())
        .overlay {
            #if os(macOS)
            if open {
                HStack(spacing: 0) {
                    Color.clear.frame(width: outside + inside).contentShape(Rectangle()).pointerStyle(.columnResize)
                    Spacer(minLength: 0)
                    Color.clear.frame(width: outside + inside).contentShape(Rectangle()).pointerStyle(.columnResize)
                }
            }
            #endif
        }
        .onTapGesture { tap(b.task.id) }
        .modifier(PressDrag(
            enabled: open,
            space: timelineSpace,
            onBegan: { p in beginBarDrag(b, at: p, left: left, top: top, lane: lane, width: width, inside: inside) },
            onChanged: { p in drag?.pointer = p },
            onEnded: { p in endDrag(at: p) },
            onCancelled: { drag = nil },
            onStill: { showMenu(b.task, rect: barRect(left: left, top: top, lane: lane, width: width)) }
        ))
        #if os(macOS)
        .contextMenu { taskMenu(b.task) }
        #else
        // A finished bar doesn't drag, but a long press still has the menu
        // (Flutter: `onLongPress` on a done bar).
        // (open bars: off, so it doesn't compete with PressDrag).
        .gesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
            showMenu(b.task, rect: barRect(left: left, top: top, lane: lane, width: width))
        }, including: open ? .subviews : .all)
        #endif
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(TimelineStyle.title(b.task))，\(TimelineStyle.dayLabel(b.start))\(b.days > 1 ? "到\(TimelineStyle.dayLabel(b.last))" : "")")
        .accessibilityAddTraits(isSelected(b.task.id) ? [.isButton, .isSelected] : .isButton)
        .accessibilityActions {
            if open {
                Button("推迟一天") { onEdit(.place(TimelinePlacement(ids: [b.task.id], days: 1, day: b.start + 1, target: nil))) }
                Button("提前一天") { onEdit(.place(TimelinePlacement(ids: [b.task.id], days: -1, day: b.start - 1, target: nil))) }
                Button(b.done ? "标记为未完成" : "完成") { onSetDone(b.task, !b.done) }
            }
        }
        .offset(x: left - outside, y: top)
        // A bar whose edge is dragged goes over its neighbours.
        .zIndex(resizing == nil ? 0 : 1)

        // Too narrow for its title: the title beside it.
        if resizing == nil && width < TimelineMetrics.titleInside {
            let room = Double(max(scale.minDays, days)) * g.dayWidth - width - 3 * TimelineMetrics.barInset
            if room > 12 {
                Text(TimelineStyle.title(b.task))
                    .font(.system(size: 12))
                    .strikethrough(b.done)
                    .foregroundStyle(b.done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .frame(width: room, height: TimelineMetrics.barHeight, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { tap(b.task.id) }
                    .offset(x: left + width + 4, y: top)
                    .accessibilityHidden(true)
            }
        }

        // While an edge is dragged: where it will start or end, beside that
        // edge, but never off the screen.
        if let r = resizing {
            let room = 96.0
            let x = r.start
                ? max(scrollX + 4, left - 6 - room)
                : min(left + width + 6, scrollX + g.width - room - 4)
            TimelinePill(text: r.start ? "从\(TimelineStyle.dayLabel(r.day))" : "到\(TimelineStyle.dayLabel(r.day))")
                .frame(width: room, height: TimelineMetrics.barHeight, alignment: r.start ? .trailing : .leading)
                .offset(x: x, y: top)
                .allowsHitTesting(false)
                .zIndex(2)
        }
    }

    /// A bar's place in the component's space.
    private func barRect(left: Double, top: Double, lane: Int, width: Double) -> CGRect {
        let lanes = layout(rows)
        let y = canvasFrame.minY + TimelineMetrics.headerHeight + lanes.lanes[lane].bodyTop + top - scrollY
        return CGRect(x: canvasFrame.minX + left - scrollX, y: y, width: width, height: TimelineMetrics.barHeight)
    }

    private func tap(_ id: String) {
        onTap(id, TimelineStyle.modifiers, order.map(\.id))
    }

    private func showMenu(_ task: TodoTask, rect: CGRect) {
        #if os(iOS)
        menu = TimelineMenu(task: task, rect: rect)
        #endif
    }

    // MARK: Dragging

    /// Puts `staged` on screen, once the canvas has its size.
    private func stage() {
        guard let staged, drag == nil, canvasFrame.height > 100, !didStage else { return }
        didStage = true
        let rows = self.rows
        let lanes = layout(rows)
        for (i, laneRows) in rows.enumerated() {
            for (r, bars) in laneRows.enumerated() {
                guard let b = bars.first(where: { $0.task.id == staged.taskId }) else { continue }
                let g = geometry
                let left = g.contentX(b.start) + TimelineMetrics.barInset
                let width = Double(b.days) * g.dayWidth - 2 * TimelineMetrics.barInset
                let top = TimelineLaneLayout.barTop(row: r)
                let rect = barRect(left: left, top: top, lane: i, width: width)
                let dx = Double(staged.days) * g.dayWidth
                switch staged.kind {
                case .move(let toLane):
                    let grab = CGPoint(x: min(30, width / 2), y: rect.height / 2)
                    let laneTop = canvasFrame.minY + TimelineMetrics.headerHeight - scrollY
                        + lanes.lanes[toLane ?? i].bodyTop + (toLane == nil ? top : TimelineLaneLayout.barTop(row: 1))
                    let p = CGPoint(x: rect.minX + grab.x + dx, y: laneTop + grab.y)
                    drag = TimelineDrag(kind: .move(lead: b.task, tasks: together(b.task), grab: grab, width: width), pointer: p)
                case .start:
                    drag = TimelineDrag(kind: .resize(bar: b, start: true, pointerX: rect.minX, scrollX: scrollX),
                                        pointer: CGPoint(x: rect.minX + dx, y: rect.midY))
                case .end:
                    drag = TimelineDrag(kind: .resize(bar: b, start: false, pointerX: rect.maxX, scrollX: scrollX),
                                        pointer: CGPoint(x: rect.maxX + dx, y: rect.midY))
                }
                return
            }
        }
    }

    @State private var didStage = false

    private var isMoving: Bool { if case .move? = drag?.kind { true } else { false } }

    private var draggedTasks: [TodoTask] {
        if case .move(let lead, let tasks, _, _)? = drag?.kind { return tasks.isEmpty ? [lead] : tasks }
        return []
    }

    /// Where an edge being dragged is now.
    private var resizeDay: Day? {
        guard let d = drag, case .resize(let bar, let start, let x0, let scroll0) = d.kind else { return nil }
        let dx = (d.pointer.x + scrollX) - (x0 + scroll0)
        return TimelineDragMath.resizedDay(bar, start: start, dx: dx, dayWidth: geometry.dayWidth)
    }

    private func together(_ lead: TodoTask) -> [TodoTask] {
        let p = picked
        return p.count > 1 && p.contains(where: { $0.id == lead.id }) ? p : []
    }

    private func beginBarDrag(_ b: TimelineBar, at p: CGPoint, left: Double, top: Double, lane: Int, width: Double, inside: Double) {
        let rect = barRect(left: left, top: top, lane: lane, width: width)
        let x = p.x - rect.minX
        if x < inside {
            drag = TimelineDrag(kind: .resize(bar: b, start: true, pointerX: p.x, scrollX: scrollX), pointer: p)
        } else if x > width - inside {
            drag = TimelineDrag(kind: .resize(bar: b, start: false, pointerX: p.x, scrollX: scrollX), pointer: p)
        } else {
            let grab = CGPoint(x: x, y: p.y - rect.minY)
            drag = TimelineDrag(kind: .move(lead: b.task, tasks: together(b.task), grab: grab, width: width), pointer: p)
        }
    }

    func beginTrayDrag(_ t: TodoTask, at p: CGPoint) {
        drag = TimelineDrag(kind: .move(lead: t, tasks: together(t), grab: CGPoint(x: 14, y: 13), width: 180), pointer: p)
    }

    /// Where a dragged task would land if let go now.
    private func dropTarget(layout: TimelineLaneLayout) -> TimelineDropTarget? {
        guard let d = drag, case .move(let lead, _, let grab, _) = d.kind else { return nil }
        let p = d.pointer
        let tasks = draggedTasks
        if trayOpen && trayFrame.contains(p) {
            return TimelineDragMath.unscheduled(tasks).isEmpty ? nil : .tray
        }
        let lanes = CGRect(
            x: canvasFrame.minX, y: canvasFrame.minY + TimelineMetrics.headerHeight,
            width: canvasFrame.width, height: lanesHeight
        )
        guard lanes.contains(p) else { return nil }
        let landing = TimelineDragMath.landing(
            lanes: timeline.lanes, layout: layout, geometry: geometry,
            contentX: p.x - canvasFrame.minX + scrollX, contentY: p.y - lanes.minY + scrollY,
            lead: lead, dragged: tasks, grabX: grab.x
        )
        return landing.map { .lane($0.lane, $0.days) }
    }

    private func endDrag(at p: CGPoint) {
        guard var d = drag else { return }
        d.pointer = p
        drag = d
        switch d.kind {
        case .move(let lead, _, _, _):
            let tasks = draggedTasks
            switch dropTarget(layout: layout(rows)) {
            case .lane(let i, let days)?:
                if let placement = TimelineDragMath.placement(dragged: tasks, lead: lead, drop: days, target: timeline.lanes[i].target) {
                    onEdit(.place(placement))
                }
            case .tray?:
                onEdit(.unschedule(TimelineDragMath.unscheduled(tasks)))
            case nil:
                break
            }
        case .resize(let bar, let start, _, _):
            if let day = resizeDay, let edit = TimelineDragMath.resizeEdit(bar.task, start: start, day: day) {
                onEdit(edit)
            }
        }
        drag = nil
    }

    /// While something is dragged near an edge of the lanes, scroll that
    /// way.
    private func autoScroll() async {
        while !Task.isCancelled, let d = drag {
            let lanes = CGRect(
                x: canvasFrame.minX, y: canvasFrame.minY + TimelineMetrics.headerHeight,
                width: canvasFrame.width, height: lanesHeight
            )
            let p = d.pointer
            if p.y >= lanes.minY - 40 && p.y <= lanes.maxY + 40 && p.x >= lanes.minX - 40 {
                let sx = TimelineDragMath.autoScrollStep(position: p.x - lanes.minX, extent: lanes.width)
                if sx != 0 {
                    let x = clampX(scrollX + sx)
                    scrollX = x
                    hPos.scrollTo(x: x)
                }
                if isMoving {
                    let sy = TimelineDragMath.autoScrollStep(position: p.y - lanes.minY, extent: lanes.height)
                    let maxY = max(layout(rows).height - lanes.height, 0)
                    if sy != 0 && maxY > 0 {
                        let y = min(max(scrollY + sy, 0), maxY)
                        scrollY = y
                        vPos.scrollTo(y: y)
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    @ViewBuilder
    private var dragPreview: some View {
        if let d = drag, case .move(let lead, _, let grab, let width) = d.kind {
            let count = draggedTasks.count
            ZStack(alignment: .topTrailing) {
                if count > 1 {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.background.secondary)
                        .frame(width: min(width, 240), height: TimelineMetrics.barHeight)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        .offset(x: 5, y: 5)
                }
                TimelineBarFace(task: lead, width: min(max(width, 120), 240), selected: true)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.background))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(Color.accentColor))
                        .offset(x: 8, y: -9)
                }
            }
            .offset(x: d.pointer.x - grab.x, y: d.pointer.y - grab.y)
        }
    }

    // MARK: 无日期

    private func tray(target: TimelineDropTarget?) -> some View {
        TimelineTray(
            groups: timeline.undated,
            titled: timeline.titled,
            highlighted: target == .tray,
            dragged: isMoving ? Set(draggedTasks.map(\.id)) : [],
            isSelected: isSelected,
            onTap: tap,
            onSetDone: onSetDone,
            onBegan: beginTrayDrag,
            onChanged: { p in drag?.pointer = p },
            onEnded: endDrag,
            onCancelled: { drag = nil },
            onStill: { t, rect in showMenu(t, rect: rect) },
            taskMenu: taskMenu
        )
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(timelineSpace)) } action: { trayFrame = $0 }
    }
}

extension TimelineView where TaskMenu == EmptyView {
    /// Without a menu for tasks.
    public init(
        timeline: Timeline,
        view: ViewRef,
        now: LocalDateTime,
        selectedTaskId: String? = nil,
        prefs: Binding<TimelinePrefs>,
        selection: TaskSelection,
        onTap: @escaping (String, TapModifiers, [String]) -> Void,
        onSetDone: @escaping (TodoTask, Bool) -> Void,
        onEdit: @escaping (TimelineEdit) -> Void,
        onNewTask: @escaping (Day, GroupTarget?) -> Void
    ) {
        self.init(
            timeline: timeline, view: view, now: now, selectedTaskId: selectedTaskId, prefs: prefs,
            selection: selection, onTap: onTap, onSetDone: onSetDone, onEdit: onEdit, onNewTask: onNewTask
        ) { _ in EmptyView() }
    }
}

// MARK: - State types

/// A drag shown as if under way (debug scenes): `taskId`'s bar moved
/// `days` days (into lane `toLane`), or one of its edges dragged.
struct TimelineStagedDrag {
    enum Kind {
        case move(toLane: Int?)
        case start
        case end
    }

    var taskId: String
    var kind: Kind
    var days: Int
}

/// The coordinate space drags and frames are measured in.
nonisolated let timelineSpace = "timeline"

struct TimelineDrag: Equatable {
    enum Kind: Equatable {
        /// Tasks being moved: the one under the pointer and the others
        /// picked with it (empty: just the lead); where the pointer holds the
        /// lead's bar, and how wide it is.
        case move(lead: TodoTask, tasks: [TodoTask], grab: CGPoint, width: Double)
        /// An edge being dragged: the left one (`start`) or the right; where
        /// the pointer and the scroll were when it began.
        case resize(bar: TimelineBar, start: Bool, pointerX: Double, scrollX: Double)
    }

    var kind: Kind
    /// In the component's space.
    var pointer: CGPoint
}

enum TimelineDropTarget: Equatable {
    case lane(Int, TimelineDropDays)
    case tray
}

struct TimelineHover: Equatable {
    var lane: Int
    var day: Day
}

struct TimelineMenu: Identifiable {
    var task: TodoTask
    var rect: CGRect
    var id: String { task.id }
}

/// Rows of a menu shown in a popover.
struct TimelineMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
    }
}

/// The red line at the current time, with a dot where it starts.
struct TimelineNowLine: View {
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Color.red).frame(width: 1.5)
            Circle().fill(Color.red).frame(width: 8, height: 8)
        }
    }
}

extension TimelineView {
    /// Debug scenes: shows `drag` as if under way.
    func staged(_ drag: TimelineStagedDrag?) -> Self {
        var v = self
        v.staged = drag
        return v
    }
}
