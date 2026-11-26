// 专注: the module's root. The big timer ring (pomodoro or stopwatch) with
// its buttons and the task it's for, today's totals and sessions; the
// records, statistics and settings open from the toolbar.
//
// A self-contained component. The timer is a value (`FocusTimer`, from the
// domain) the caller keeps: every change comes back through
// `onTimerChange` to be saved, and the timer passed in on the next launch
// carries on where the clock says it is. Finished sessions, deleted ones
// (tombstoned) and ones typed in come back through `onSaveSession`.
// `onEndScheduled` gives the moment the running pomodoro or break will end
// (nil: nothing running) for the caller to schedule a notification.
// `onPickTask` lets the caller present its own task picker and call back
// with the choice; without it a simple list of `tasks` is offered.
//
//     FocusRootView(timer: saved, settings: settings, sessions: sessions,
//                   tasks: openTasks, lists: lists,
//                   onTimerChange: store.saveTimer, onSaveSession: repo.save,
//                   onSettingsChange: store.saveSettings,
//                   onEndScheduled: notifier.scheduleFocusEnd)

import OpenTodoDomain
import SwiftUI

public struct FocusRootView: View {
    public var timer: FocusTimer
    public var settings: FocusSettings
    public var sessions: [FocusSession]
    public var tasks: [TodoTask]
    public var lists: [TaskList]
    public var timeZone: TimeZone
    public var onTimerChange: (FocusTimer) -> Void
    public var onSaveSession: (FocusSession) -> Void
    public var onSettingsChange: (FocusSettings) -> Void
    public var onPickTask: ((@escaping (TodoTask?) -> Void) -> Void)?
    public var onEndScheduled: (Date?) -> Void
    var clock: () -> Int
    /// Whether this view runs the clock itself (records what runs out).
    /// In the app the shared `FocusTimerStore` does, so two windows don't
    /// both record it; the view just shows the timer it's given.
    var selfTicking = true

    @State private var current: FocusTimer
    @State private var path: [FocusPage]
    @State private var confirmingAbandon = false
    @State private var pickingTask = false

    public init(
        timer: FocusTimer,
        settings: FocusSettings,
        sessions: [FocusSession],
        tasks: [TodoTask] = [],
        lists: [TaskList] = [],
        timeZone: TimeZone = .current,
        onTimerChange: @escaping (FocusTimer) -> Void,
        onSaveSession: @escaping (FocusSession) -> Void,
        onSettingsChange: @escaping (FocusSettings) -> Void,
        onPickTask: ((@escaping (TodoTask?) -> Void) -> Void)? = nil,
        onEndScheduled: @escaping (Date?) -> Void = { _ in }
    ) {
        self.init(timer: timer, settings: settings, sessions: sessions, tasks: tasks, lists: lists, timeZone: timeZone,
                  onTimerChange: onTimerChange, onSaveSession: onSaveSession, onSettingsChange: onSettingsChange,
                  onPickTask: onPickTask, onEndScheduled: onEndScheduled, clock: millisNow, start: nil)
    }

    init(
        timer: FocusTimer, settings: FocusSettings, sessions: [FocusSession], tasks: [TodoTask], lists: [TaskList],
        timeZone: TimeZone, onTimerChange: @escaping (FocusTimer) -> Void, onSaveSession: @escaping (FocusSession) -> Void,
        onSettingsChange: @escaping (FocusSettings) -> Void, onPickTask: ((@escaping (TodoTask?) -> Void) -> Void)?,
        onEndScheduled: @escaping (Date?) -> Void, clock: @escaping () -> Int, start: FocusPage?,
        selfTicking: Bool = true
    ) {
        self.selfTicking = selfTicking
        self.timer = timer
        self.settings = settings
        self.sessions = sessions
        self.tasks = tasks
        self.lists = lists
        self.timeZone = timeZone
        self.onTimerChange = onTimerChange
        self.onSaveSession = onSaveSession
        self.onSettingsChange = onSettingsChange
        self.onPickTask = onPickTask
        self.onEndScheduled = onEndScheduled
        self.clock = clock
        var t = timer
        // A running timer keeps the settings it started with.
        if t.phase == .idle { t.settings = settings }
        _current = State(initialValue: t)
        _path = State(initialValue: start.map { [$0] } ?? [])
    }

    private var today: Day { Day(Date(timeIntervalSince1970: Double(clock()) / 1000), in: timeZone) }

    public var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("模式", selection: modeBinding) {
                        Text("番茄").tag(FocusKind.pomodoro)
                        Text("正计时").tag(FocusKind.stopwatch)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 240)
                    .disabled(current.phase != .idle)

                    SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                        let now = Int(context.date.timeIntervalSince1970 * 1000)
                        FocusRing(timer: current, now: now, taskTitle: taskTitle, onTask: chooseTask)
                    }
                    .frame(maxWidth: 320)

                    controls
                    if current.mode == .pomodoro { cycleDots }
                    summaryTiles(focusSummary(sessions, on: today, in: timeZone))
                    todaySessions
                }
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color.groupedBackground)
            .navigationTitle("专注")
            .efficiencyTitleMenu()
            .toolbar {
                ToolbarItem(placement: .moreActions) {
                    Button("专注记录", systemImage: "list.bullet.rectangle") { path.append(.records) }
                }
                ToolbarItem(placement: .moreActions) {
                    Button("专注设置", systemImage: "gearshape") { path.append(.settings) }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("统计", systemImage: "chart.bar.xaxis") { path.append(.stats) }
                }
            }
            .navigationDestination(for: FocusPage.self) { page in
                switch page {
                case .stats:
                    FocusStatsView(sessions: sessions, tasks: tasks, lists: lists, today: today, timeZone: timeZone)
                case .records:
                    FocusRecordsView(sessions: sessions, tasks: tasks, today: today, timeZone: timeZone,
                                     onSaveSession: onSaveSession, clock: clock)
                case .settings:
                    FocusSettingsView(settings: settings, onChange: changeSettings)
                }
            }
        }
        .confirmationDialog("放弃这次专注？", isPresented: $confirmingAbandon, titleVisibility: .visible) {
            Button("放弃", role: .destructive) { perform(.abandon) }
        } message: {
            Text(current.elapsed(at: clock()) >= focusMinimumSeconds
                ? "已专注的时间会记下来，但不算一个番茄。"
                : "不足\(focusMinimumSeconds / 60)分钟，不会记录。")
        }
        .sheet(isPresented: $pickingTask) {
            FocusTaskPicker(tasks: tasks, lists: lists, selected: current.taskId) { t in
                setTask(t)
            }
        }
        .task(id: current.isRunning) {
            guard selfTicking else { return }
            catchUp()
            while current.isRunning, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                catchUp()
            }
        }
        .onChange(of: timer) { _, new in
            var t = new
            if t.phase == .idle { t.settings = settings }
            if t != current { current = t }
        }
        .onChange(of: settings) { _, new in
            guard current.phase == .idle else { return }
            current.settings = new
            onTimerChange(current)
        }
    }

    // MARK: Parts

    private var modeBinding: Binding<FocusKind> {
        Binding(get: { current.mode }, set: { m in
            current.setMode(m)
            onTimerChange(current)
        })
    }

    private var controls: some View {
        let cs = focusControls(current)
        return HStack(spacing: 16) {
            ForEach(Array(cs.enumerated()), id: \.element) { i, c in
                if i == 0 {
                    Button {
                        perform(c)
                    } label: {
                        Label(c.title, systemImage: c.symbol)
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: c == .abandon ? .destructive : nil) {
                        if c == .abandon { confirmingAbandon = true } else { perform(c) }
                    } label: {
                        Label(c.title, systemImage: c.symbol)
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .animation(.snappy, value: cs)
    }

    private var cycleDots: some View {
        let (done, total) = focusCycleDots(current)
        return HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < done ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("距长休息还有\(total - done)个番茄"))
    }

    private func summaryTiles(_ s: FocusSummary) -> some View {
        Grid(horizontalSpacing: 12) {
            GridRow {
                StatTile(title: "今日专注", value: durationText(s.seconds), unit: "", symbol: "clock.fill", tint: .accentColor)
                StatTile(title: "今日番茄", value: "\(s.pomodoros)", unit: "个", symbol: "timer", tint: .red)
            }
        }
    }

    @ViewBuilder
    private var todaySessions: some View {
        let todays = focusSessions(sessions, from: today, through: today, in: timeZone).sorted { $0.startedAt > $1.startedAt }
        if !todays.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("今天的专注").font(.headline)
                    Spacer()
                    Button("全部记录") { path.append(.records) }.font(.subheadline)
                }
                .padding(.bottom, 8)
                ForEach(todays.prefix(5)) { s in
                    FocusSessionRow(session: s, taskTitle: tasks.first { $0.id == s.taskId }?.title, timeZone: timeZone)
                        .padding(.vertical, 6)
                    if s.id != todays.prefix(5).last?.id { Divider() }
                }
            }
            .panel()
        }
    }

    private var taskTitle: String? {
        current.taskId.flatMap { id in tasks.first { $0.id == id }?.title ?? "已删除的任务" }
    }

    // MARK: Actions

    private func perform(_ c: FocusControl) {
        // Settings changed while the timer ran take effect from the next start.
        if current.phase == .idle { current.settings = settings }
        if let s = applyFocusControl(c, to: &current, at: clock()) { onSaveSession(s) }
        onTimerChange(current)
        scheduleEnd()
    }

    /// Records whatever ran out since the last look.
    private func catchUp() {
        let recorded = current.tick(at: clock())
        guard !recorded.isEmpty else { return }
        recorded.forEach(onSaveSession)
        if settings.endSound { playFocusEndSound() }
        onTimerChange(current)
        scheduleEnd()
    }

    private func scheduleEnd() {
        onEndScheduled(current.endsAt(at: clock()).map { Date(timeIntervalSince1970: Double($0) / 1000) })
    }

    private func chooseTask() {
        if let onPickTask {
            onPickTask { setTask($0) }
        } else {
            pickingTask = true
        }
    }

    private func setTask(_ t: TodoTask?) {
        current.taskId = t?.id
        onTimerChange(current)
    }

    private func changeSettings(_ s: FocusSettings) {
        onSettingsChange(s)
    }
}

/// The pages the focus root pushes.
enum FocusPage: Hashable {
    case stats
    case records
    case settings
}

// MARK: - Ring

struct FocusRing: View {
    var timer: FocusTimer
    var now: Int
    var taskTitle: String?
    var onTask: () -> Void

    private var tint: Color {
        if case .resting = timer.phase { return .green }
        return timer.phase == .paused ? .orange : .accentColor
    }

    var body: some View {
        let progress = timer.progress(at: now)
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.14), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress ?? (timer.phase == .idle ? 0 : 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            VStack(spacing: 10) {
                Text(focusPhaseTitle(timer))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(clockText(focusClockSeconds(timer, at: now)))
                    .font(.system(size: 60, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: timer.mode == .pomodoro))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Button(action: onTask) {
                    Label(taskTitle ?? "选择任务", systemImage: taskTitle == nil ? "plus.circle" : "checklist")
                        .font(.subheadline)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12), in: .capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(taskTitle == nil ? .secondary : .primary)
                .frame(maxWidth: 200)
            }
            .padding(36)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Session row

struct FocusSessionRow: View {
    var session: FocusSession
    var taskTitle: String?
    var timeZone: TimeZone

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.kind == .stopwatch ? "stopwatch.fill" : (session.completed ? "timer" : "timer.circle"))
                .font(.body)
                .foregroundStyle(session.kind == .pomodoro && session.completed ? Color.red : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(taskTitle ?? (session.note.isEmpty ? "专注" : session.note)).lineLimit(1)
                Text(focusTimeRange(session, in: timeZone) + (session.kind == .pomodoro && !session.completed ? " · 未完成" : ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Text(durationText(session.duration))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Task picker

/// The built-in task picker, used when the caller doesn't give its own:
/// the open tasks, searchable.
struct FocusTaskPicker: View {
    var tasks: [TodoTask]
    var lists: [TaskList]
    var selected: String?
    var onPick: (TodoTask?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var shown: [TodoTask] {
        tasks.filter { isOpen($0) && $0.deletedAt == nil && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        NavigationStack {
            List {
                if selected != nil {
                    Button("不关联任务", systemImage: "minus.circle") {
                        onPick(nil)
                        dismiss()
                    }
                }
                ForEach(shown) { t in
                    Button {
                        onPick(t)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).foregroundStyle(.primary)
                                Text(lists.first { $0.id == t.listId }?.name ?? "收集箱").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if t.id == selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if shown.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, prompt: "搜索任务")
            .navigationTitle("专注于")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
    }
}
