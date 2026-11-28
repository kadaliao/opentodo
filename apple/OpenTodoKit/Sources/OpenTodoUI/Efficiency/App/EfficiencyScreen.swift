// The four efficiency modules in the app (四象限, 专注, 习惯, 倒数日): their
// screens over the real data (`model.efficiency`, `model.data`), how they
// sit in the window, and the bits they put elsewhere (开始专注 in a task's
// menu, the countdowns at the top of 今天, a word of news in the Mac
// sidebar).
//
// Layout. Each module's screen is a `NavigationStack` of its own and fills
// what it is given: on macOS the window's detail column, beside the one
// sidebar where the four are rows (Shell/MacShell.swift); on iPad a tab
// each. Compact (iPhone): the four share one tab, 效率, beside 任务 / 日历 /
// 搜索 (seven tabs don't fit); the tab shows the module last used and the
// navigation title is a menu to switch, the way Photos and Files switch
// what they show.

import OpenTodoData
import OpenTodoDomain
import SwiftUI

extension AppModule {
    /// 四象限, 专注, 习惯, 倒数日, in the order of the cases.
    public static var efficiencyModules: [AppModule] { allCases.filter(\.isEfficiency) }

    public var isEfficiency: Bool {
        switch self {
        case .matrix, .focus, .habits, .countdowns: true
        default: false
        }
    }

    /// The tabs: every module, or (compact) the efficiency ones folded
    /// into one tab that stands for `current` when that's one of them, else
    /// for `last`.
    public static func tabs(compact: Bool, current: AppModule, last: AppModule) -> [AppModule] {
        guard compact else { return allCases }
        let shown = current.isEfficiency ? current : last
        var out: [AppModule] = []
        for m in allCases {
            if !m.isEfficiency { out.append(m) } else if !out.contains(where: \.isEfficiency) { out.append(shown) }
        }
        return out
    }

    func tabTitle(compact: Bool) -> String { compact && isEfficiency ? "效率" : title }
    func tabSymbol(compact: Bool) -> String { compact && isEfficiency ? "bolt" : symbol }
}

// MARK: - The screen

/// What `ModuleScreen` shows for an efficiency module.
struct EfficiencyScreen: View {
    @Environment(AppModel.self) private var model
    var module: AppModule

    var body: some View {
        content
            // A phone's title menu switches between the four.
            .environment(\.efficiencySwitcher, model.width == .compact ? EfficiencySwitcher { model.switchTo($0) } : nil)
            // Also when the Mac sidebar goes from one of the four to another
            // (the same view, another `module`).
            .onChange(of: module, initial: true) {
                model.efficiency.lastModule = module
                // A start (debug route, a tap on 今天) is used once.
                model.efficiency.pendingStart[module] = nil
            }
            .onChange(of: model.efficiency.openToken) { model.efficiency.pendingStart[module] = nil }
    }

    @ViewBuilder private var content: some View {
        let eff = model.efficiency
        let start = eff.pendingStart[module]
        // A new `openToken` (a notification opened) builds the screen afresh
        // so it starts where it was asked to.
        let id = "\(module.rawValue)-\(eff.openToken)"
        switch module {
        case .habits:
            HabitsRootView(
                habits: eff.habits, checkins: eff.checkins, today: model.today,
                onSaveHabit: eff.saveHabit, onSaveCheckin: eff.saveCheckin,
                newId: { model.repo.newId() }, clock: { eff.nowMillis }, start: habitsStart(start)
            )
            .id(id)
        case .focus:
            FocusRootView(
                timer: eff.timer, settings: model.settings.focusSettings, sessions: eff.sessions,
                tasks: model.data.tasks.filter { $0.trashedAt == nil }, lists: model.lists, timeZone: model.timeZone,
                onTimerChange: eff.timerChanged, onSaveSession: eff.saveSession, onSettingsChange: eff.setFocusSettings,
                onPickTask: nil, onEndScheduled: { _ in }, clock: { eff.nowMillis }, start: focusStart(start),
                selfTicking: false
            )
            .id(id)
        case .countdowns:
            CountdownsRootView(
                countdowns: eff.countdowns, today: model.today, onSave: eff.saveCountdown,
                formats: eff.countdownFormats, onFormatChange: { eff.countdownFormats[$0] = $1 },
                newId: { model.repo.newId() }, clock: { eff.nowMillis }, start: countdownsStart(start)
            )
            .id(id)
        case .matrix:
            MatrixRootView(
                tasks: model.data.tasks, prefs: model.settings.matrixPrefs, now: model.now, lists: model.lists,
                onToggleDone: { t in model.run { await model.setDone(t, true) } },
                onOpenTask: { model.revealTask($0.id) },
                onMoveTask: { _, new in model.run { try await model.repo.updateTask(new.id) { $0.takeMatrixMove(new) } } },
                onQuickAdd: { title, d in
                    model.run {
                        _ = await model.quickAdd(title, target: QuickAddTarget(listId: d.listId, date: d.date, tags: d.tags, priority: d.priority))
                    }
                },
                onPrefsChange: { model.settings.setMatrixPrefs($0) },
                onReorder: { orders, switchToManual in
                    model.run {
                        if !orders.isEmpty { try await model.repo.dropInto(Array(orders.keys), .order, orders) }
                        // After the orders are in, so nothing re-sorts for a moment.
                        if switchToManual {
                            var p = model.settings.matrixPrefs
                            p.manualOrder = true
                            model.settings.setMatrixPrefs(p)
                        }
                    }
                },
                ruleEditor: filterRuleEditor, start: matrixStart(start)
            )
            .id(id)
        default:
            EmptyView()
        }
    }

    /// The saved-filter editor, for a quadrant's name and rule.
    private var filterRuleEditor: MatrixRuleEditor {
        { [model] quadrant, done in
            AnyView(FilterEditor(
                filter: TaskFilter(id: "matrix", name: quadrant.name, rule: quadrant.rule),
                lists: model.lists, tags: model.tags, tasks: model.data.tasks, now: model.now,
                onSave: { r in done(MatrixQuadrant(name: r.name, rule: r.rule)) },
                title: "编辑象限"
            ))
        }
    }

    // MARK: Debug and 今天 starts

    private func habitsStart(_ s: String?) -> HabitsRootView.Start {
        switch s {
        case "edit": .editor(model.efficiency.habits.first?.id)
        case "new": .editor(nil)
        case "all": .all
        // The screen is built before the habits are read: fall back to the
        // demo's first habit rather than to none.
        case let x? where x.hasPrefix("detail"):
            .detail(String(x.dropFirst("detail:".count)).nonEmpty ?? model.efficiency.habits.first?.id ?? "h-wake")
        default: .today
        }
    }

    private func focusStart(_ s: String?) -> FocusPage? {
        switch s {
        case "stats": .stats
        case "records": .records
        case "settings": .settings
        default: nil
        }
    }

    private func countdownsStart(_ s: String?) -> CountdownsRootView.Start {
        let first = sortCountdowns(model.efficiency.countdowns, today: model.today).first?.id
        switch s {
        case "edit": return .editor(first)
        case "new": return .editor(nil)
        case let x? where x.hasPrefix("detail"):
            return .detail(String(x.dropFirst("detail:".count)).nonEmpty ?? first ?? "c-together")
        default: return .cards
        }
    }

    private func matrixStart(_ s: String?) -> MatrixRootView.Start {
        switch s {
        case "quadrant": .quadrant(0)
        case "edit": .edit
        default: .grid
        }
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}

extension TodoTask {
    /// What dropping into a quadrant changes (`movedIntoQuadrant`).
    nonisolated mutating func takeMatrixMove(_ t: TodoTask) {
        priority = t.priority
        listId = t.listId
        sectionId = t.sectionId
        tags = t.tags
        dueDate = t.dueDate
    }
}

// MARK: - Switching on a phone

/// How the 效率 tab's title menu switches modules.
struct EfficiencySwitcher {
    var choose: @MainActor (AppModule) -> Void
}

extension EnvironmentValues {
    @Entry var efficiencySwitcher: EfficiencySwitcher? = nil
}

private struct EfficiencyTitleMenu: ViewModifier {
    @Environment(\.efficiencySwitcher) private var switcher

    func body(content: Content) -> some View {
        if let switcher {
            content.toolbarTitleMenu {
                ForEach(AppModule.efficiencyModules) { m in
                    Button(m.title, systemImage: m.symbol) { switcher.choose(m) }
                }
            }
            #if os(iOS)
            // A large title doesn't show the menu's chevron, so nothing
            // said the title switches modules (习惯 / 专注 / 倒数日 had
            // no way to the others).
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } else {
            content
        }
    }
}

extension View {
    /// On a phone, the navigation title switches between the efficiency
    /// modules. The module screens put this on their first page.
    func efficiencyTitleMenu() -> some View { modifier(EfficiencyTitleMenu()) }
}

// MARK: - News

/// A line about a module (the tooltip of its row in the Mac sidebar):
/// 今天 3/5, 专注中, 春节 还有 72 天 ….
@MainActor
func efficiencySummary(_ m: AppModule, model: AppModel) -> String {
    let eff = model.efficiency
    let today = model.today
    switch m {
    case .habits:
        let (done, due) = dayCompletion(eff.habits, checkins: eff.checkins, on: today)
        return due == 0 ? "今天没有要打卡的" : "今天 \(done)/\(due)"
    case .focus:
        if eff.timer.phase != .idle { return focusPhaseTitle(eff.timer) }
        let s = focusSummary(eff.sessions, on: today, in: model.timeZone)
        return s.seconds == 0 ? "今天还没专注" : "今天 \(durationText(s.seconds))"
    case .countdowns:
        guard let c = sortCountdowns(eff.countdowns, today: today).first(where: { countdownStatus($0, today: today)?.past == false }),
              let s = countdownStatus(c, today: today)
        else { return eff.countdowns.isEmpty ? "还没有倒数日" : "" }
        return s.days == 0 ? "\(c.title) 就是今天" : "\(c.title) 还有\(s.days)天"
    case .matrix:
        let cell = matrixCells(model.data.tasks, prefs: model.settings.matrixPrefs, now: model.now)[0]
        return "\(cell.name) \(cell.tasks.count)"
    default:
        return ""
    }
}

/// The word at the end of a module's row in the Mac sidebar: today's
/// check-ins (2/5), the timer when it isn't idle (专注中), 今天 when a
/// countdown's day has come. Nil: nothing worth a glance.
@MainActor
func moduleBadge(_ m: AppModule, model: AppModel) -> String? {
    let eff = model.efficiency
    switch m {
    case .habits:
        let (done, due) = dayCompletion(eff.habits, checkins: eff.checkins, on: model.today)
        return due == 0 ? nil : "\(done)/\(due)"
    case .focus:
        return eff.timer.phase == .idle ? nil : focusPhaseTitle(eff.timer)
    case .countdowns:
        let today = model.today
        return eff.countdowns.contains { countdownStatus($0, today: today).map { !$0.past && $0.days == 0 } ?? false } ? "今天" : nil
    default:
        return nil
    }
}

// MARK: - 今天

/// The countdowns marked 显示在“今天” whose day is today, as a row at the
/// top of 今天; a tap opens the countdown.
struct TodayCountdownsRow: View {
    @Environment(\.uiScale) private var s
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.efficiency.todayCountdowns(model.today)
        if !items.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8 * s) {
                    ForEach(items) { c in
                        Button {
                            model.efficiency.open(.countdowns, detail: c.id, in: model)
                        } label: {
                            HStack(spacing: 6 * s) {
                                EmojiBadge(emoji: c.emoji, color: c.color, fallback: countdownSymbol(c.kind), size: 22)
                                Text(c.title).lineLimit(1)
                                Text(todayCountdownCaption(c, today: model.today))
                                    .foregroundStyle(.secondary)
                            }
                            .uiFont(.subheadline)
                            .padding(.vertical, 6 * s)
                            .padding(.horizontal, 10 * s)
                            .background(EfficiencyPalette.color(c.color).opacity(0.12), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .listRowSeparator(.hidden)
            .selectionDisabled()
            .accessibilityLabel(Text("今天的倒数日"))
        }
    }
}

/// 26岁生日 / 3周年 / 今天.
func todayCountdownCaption(_ c: Countdown, today: Day) -> String {
    switch c.kind {
    case .birthday:
        if let age = countdownAge(c, on: today), age > 0 { return "\(age)岁生日" }
        return "生日"
    case .anniversary:
        let years = calendarSpan(c.date, today).years
        return years > 0 && c.date < today ? "\(years)周年" : "今天"
    default:
        return "今天"
    }
}

// MARK: - 开始专注

/// The 开始专注 item of a task's menu.
struct StartFocusButton: View {
    @Environment(AppModel.self) private var model
    var task: TodoTask

    var body: some View {
        if task.status == .open && task.trashedAt == nil {
            Button("开始专注", systemImage: "timer") {
                model.efficiency.start(model)
                model.efficiency.startFocus(on: task)
            }
        }
    }
}
