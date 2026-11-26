// The calendar module's main view: the view of the mode (日 / 3天 / 周 / 多周
// / 月 / 年 / 日程), the toolbar to change mode and page, the keys of a
// computer, the 安排任务 inspector, and the sheets a phone uses instead of
// popovers. Put it in a navigation container (the detail column of a
// split view, or a NavigationStack on a phone): it fills the toolbar and the
// title. See `CalendarModel.swift` for how to wire it up. Port of
// `calendar_screen.dart`.

import OpenTodoDomain
import SwiftUI

public struct CalendarView: View {
    @Bindable var model: CalendarModel
    let tasks: [TodoTask]
    let lists: [TaskList]
    let filters: [TaskFilter]
    let now: LocalDateTime
    let actions: CalendarActions
    let options: CalendarOptions

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #else
    /// Too narrow for the seven segments beside the title and the
    /// buttons: the views in a pop-up menu instead (otherwise the toolbar
    /// put them all, 今天 and the arrows too, behind its » button).
    @State private var narrowToolbar = false
    #endif
    @FocusState private var focused: Bool

    public init(
        model: CalendarModel,
        tasks: [TodoTask],
        lists: [TaskList] = [],
        filters: [TaskFilter] = [],
        now: LocalDateTime,
        actions: CalendarActions = CalendarActions(),
        options: CalendarOptions = CalendarOptions()
    ) {
        self.model = model
        self.tasks = tasks
        self.lists = lists
        self.filters = filters
        self.now = now
        self.actions = actions
        self.options = options
    }

    private var compact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    public var body: some View {
        let ctx = CalendarContext(
            model: model, tasks: tasks, lists: Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
            filters: filters, now: now, actions: actions, options: options, compact: compact
        )
        content(ctx)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(macOS)
            .onGeometryChange(for: Bool.self) { $0.size.width < 820 } action: { narrowToolbar = $0 }
            #endif
            .onChange(of: compact, initial: true) { model.compact = compact }
            .navigationTitle(calendarTitle(model.mode, model.anchor, weeks: model.prefs.weeks))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu { pageButtons(ctx) }
            #endif
            .toolbar { toolbar(ctx) }
            #if os(macOS)
            .navigationSubtitle(model.selection.isActive ? "已选择 \(model.selection.ids.count) 项" : "")
            #endif
            .modifier(ArrangePanelPresentation(isPresented: $model.showsArrangePanel, compact: compact, ctx: ctx))
            .sheet(item: Binding(get: { compact ? model.newTask : nil }, set: { model.newTask = $0 })) { request in
                NewTaskPanel(ctx: ctx, request: request)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: Binding(get: { compact && model.cardTaskId != nil }, set: { if !$0 { model.closeCard() } })) {
                if let id = model.cardTaskId, let task = tasks.first(where: { $0.id == id }) {
                    TaskCard(task: task, ctx: ctx)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
            #if os(macOS)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in handle(press, ctx) }
            .onAppear { focused = true }
            #endif
    }

    @ViewBuilder private func content(_ ctx: CalendarContext) -> some View {
        let range = model.range
        switch model.mode {
        case .month:
            if compact {
                PhoneMonth(ctx: ctx)
            } else {
                MonthBoard(ctx: ctx, range: range, month: (model.anchor.year, model.anchor.month))
            }
        case .multiWeek:
            MonthBoard(ctx: ctx, range: range, month: nil)
        case .day, .threeDays, .week:
            TimeGrid(ctx: ctx, range: range).id(model.mode)
        case .agenda:
            AgendaView(ctx: ctx, range: range)
        case .year:
            YearView(ctx: ctx)
        }
    }

    /// The tasks shown, in order, for Shift-click ranges and ⌘A: on the
    /// phone's month, the day below it.
    private func pageOrder(_ ctx: CalendarContext) -> [String] {
        model.pageOrder(tasks: tasks, filters: filters, now: now, compact: compact)
    }

    private func perform(_ command: CalendarCommand, _ ctx: CalendarContext) {
        withAnimation(.snappy(duration: 0.2)) {
            model.perform(command, today: ctx.today, order: command == .selectAll ? pageOrder(ctx) : [])
        }
    }

    #if os(macOS)
    private func handle(_ press: KeyPress, _ ctx: CalendarContext) -> KeyPress.Result {
        let key: CalendarKey? = switch press.key {
        case .leftArrow: .left
        case .rightArrow: .right
        case .escape: .escape
        default: press.characters.first.map { .character($0) }
        }
        guard let key else { return .ignored }
        let command = press.modifiers.contains(.command)
        if press.modifiers.contains(.option) || press.modifiers.contains(.control) { return .ignored }
        guard let c = CalendarLogic.command(for: key, command: command) else { return .ignored }
        if c == .clearPicking && !model.selection.isActive && !model.selection.isPicking { return .ignored }
        perform(c, ctx)
        return .handled
    }
    #endif

    // MARK: Toolbar

    @ToolbarContentBuilder private func toolbar(_ ctx: CalendarContext) -> some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .principal) {
            let picker = Picker("视图", selection: $model.mode) {
                ForEach(CalendarLogic.modesOffered, id: \.self) { m in
                    Text(m.label).tag(m)
                }
            }
            Group {
                if narrowToolbar {
                    picker.pickerStyle(.menu)
                } else {
                    picker.pickerStyle(.segmented)
                }
            }
            .fixedSize()
            .help("切换视图（D 3 W M Y A）")
        }
        ToolbarItem(placement: .navigation) {
            ControlGroup {
                Button { perform(.page(-1), ctx) } label: { Label("上一页", systemImage: "chevron.left") }
                    .help("上一页（←）")
                Button("今天") { perform(.today, ctx) }
                    .help("今天（T）")
                Button { perform(.page(1), ctx) } label: { Label("下一页", systemImage: "chevron.right") }
                    .help("下一页（→）")
            }
        }
        #else
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("视图", selection: $model.mode) {
                    ForEach(CalendarLogic.modesOffered(compact: compact), id: \.self) { m in
                        Label(m.label, systemImage: CalendarLogic.modeSymbol(m)).tag(m)
                    }
                }
            } label: {
                Label(model.mode.label, systemImage: CalendarLogic.modeSymbol(model.mode))
            }
            .accessibilityLabel("切换视图")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("今天") { perform(.today, ctx) }
        }
        #endif
        if model.selection.isActive || model.selection.isPicking {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    perform(.clearPicking, ctx)
                } label: {
                    #if os(macOS)
                    Label("取消选择", systemImage: "xmark.circle")
                    #else
                    Text("完成")
                    #endif
                }
                .help("取消选择（Esc）")
            }
        }
        // While picking on a phone the bottom bar has the room (Flutter hides the FAB).
        if !(compact && (model.selection.isActive || model.selection.isPicking)) {
        ToolbarItem(placement: .primaryAction) {
            Button {
                ctx.startNewTask(CalendarNewTask(date: CalendarLogic.defaultNewDay(
                    mode: model.mode, range: model.range, anchor: model.anchor, today: ctx.today, compact: compact
                ), time: nil))
            } label: {
                Label("添加任务", systemImage: "plus")
            }
            .help("添加任务")
        }
        }
        ToolbarItem(placement: .primaryAction) {
            moreMenu(ctx)
        }
    }

    @ViewBuilder private func pageButtons(_ ctx: CalendarContext) -> some View {
        Button { perform(.page(-1), ctx) } label: { Label("上一页", systemImage: "chevron.left") }
        Button { perform(.today, ctx) } label: { Label("今天", systemImage: "calendar.circle") }
        Button { perform(.page(1), ctx) } label: { Label("下一页", systemImage: "chevron.right") }
    }

    private func moreMenu(_ ctx: CalendarContext) -> some View {
        Menu {
            Toggle(isOn: $model.showsArrangePanel) { Label("安排任务", systemImage: "tray.and.arrow.down") }
            if model.mode == .multiWeek {
                Picker("显示几周", selection: $model.prefs.weeks) {
                    ForEach(Array(multiWeekRange), id: \.self) { n in Text(verbatim: "\(n) 周").tag(n) }
                }
            }
            // Always here, as in Flutter's ⋯ (the sidebar can be hidden).
            Section {
                CalendarDisplayToggles(model: model)
            }
            if options.filtersInToolbar || compact {
                Menu("显示的清单") {
                    CalendarListToggles(model: model, lists: lists)
                }
            }
            Section {
                CalendarFilterPicker(model: model, filters: filters)
                if options.taskTap == nil {
                    Picker(selection: $model.prefs.taskCard) {
                        Text("打开详情").tag(false)
                        Text("显示卡片").tag(true)
                    } label: {
                        Label("点任务时", systemImage: "hand.tap")
                    }
                }
            }
        } label: {
            Label("更多", systemImage: "ellipsis.circle")
        }
        .help("更多")
    }
}

/// The 安排任务 panel: an inspector beside the calendar; on a phone a sheet
/// of its own. (As an inspector on a phone its title took over the
/// calendar's month title even while it was closed.)
private struct ArrangePanelPresentation: ViewModifier {
    @Environment(\.uiScale) private var s
    @Binding var isPresented: Bool
    let compact: Bool
    let ctx: CalendarContext

    func body(content: Content) -> some View {
        #if os(iOS)
        if compact {
            content.sheet(isPresented: $isPresented) {
                NavigationStack {
                    ArrangePanel(ctx: ctx)
                        .navigationTitle("安排任务")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { isPresented = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        } else {
            content.inspector(isPresented: $isPresented) {
                ArrangePanel(ctx: ctx)
                    .inspectorColumnWidth(min: 240, ideal: 280 * s, max: 360 * s)
            }
        }
        #else
        content.inspector(isPresented: $isPresented) {
            ArrangePanel(ctx: ctx)
                .inspectorColumnWidth(min: 240, ideal: 280 * s, max: 360 * s)
        }
        #endif
    }
}
