// 习惯: the module's root. The habits to check in on a day (today, or one of
// the six before it, picked on the week strip), by part of the day; the
// editor, the detail page and the list of all habits open from here.
//
// A self-contained component: it gets the records and today, and hands back
// every change as a whole record to write (`onSaveHabit`, `onSaveCheckin`;
// archiving sets `archivedAt`, deleting and taking back a check-in set
// `deletedAt`). It never touches the database.
//
//     HabitsRootView(habits: habits, checkins: checkins, today: today,
//                    onSaveHabit: repo.save, onSaveCheckin: repo.save)

import OpenTodoDomain
import SwiftUI

public struct HabitsRootView: View {
    @Environment(\.uiScale) private var s
    public var habits: [Habit]
    public var checkins: [HabitCheckin]
    public var today: Day
    public var onSaveHabit: (Habit) -> Void
    public var onSaveCheckin: (HabitCheckin) -> Void
    /// Epoch ms for the records' stamps.
    var clock: () -> Int
    /// Ids for new habits (UUID v7 in the app).
    var newId: () -> String

    @State private var selected: Day
    @State private var path: [String]
    @State private var editor: HabitEditorTarget?
    @State private var showingAll: Bool
    @State private var amount: AmountPrompt?

    public init(
        habits: [Habit],
        checkins: [HabitCheckin],
        today: Day,
        onSaveHabit: @escaping (Habit) -> Void,
        onSaveCheckin: @escaping (HabitCheckin) -> Void,
        newId: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.init(habits: habits, checkins: checkins, today: today, onSaveHabit: onSaveHabit,
                  onSaveCheckin: onSaveCheckin, newId: newId, clock: millisNow, start: .today)
    }

    /// Where the debug routes open it.
    enum Start: Hashable {
        case today
        case detail(String)
        case editor(String?)
        case all
    }

    init(
        habits: [Habit], checkins: [HabitCheckin], today: Day,
        onSaveHabit: @escaping (Habit) -> Void, onSaveCheckin: @escaping (HabitCheckin) -> Void,
        newId: @escaping () -> String, clock: @escaping () -> Int, start: Start
    ) {
        self.habits = habits
        self.checkins = checkins
        self.today = today
        self.onSaveHabit = onSaveHabit
        self.onSaveCheckin = onSaveCheckin
        self.newId = newId
        self.clock = clock
        _selected = State(initialValue: today)
        switch start {
        case .detail(let id): _path = State(initialValue: [id])
        default: _path = State(initialValue: [])
        }
        switch start {
        case .editor(let id): _editor = State(initialValue: HabitEditorTarget(habitId: id))
        default: _editor = State(initialValue: nil)
        }
        _showingAll = State(initialValue: start == .all)
    }

    private var live: [Habit] { habits.filter { $0.deletedAt == nil } }

    public var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    WeekStrip(
                        days: recentDays(today),
                        today: today,
                        selected: $selected,
                        completion: { dayCompletion(live, checkins: checkins, on: $0) }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                let groups = todayHabits(live, checkins: checkins, today: selected)
                if groups.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label(live.isEmpty ? "还没有习惯" : "这天没有要打卡的习惯", systemImage: "leaf")
                        } description: {
                            Text(live.isEmpty ? "从一件每天都能做到的小事开始。" : "休息一下，或者去看看全部习惯。")
                        } actions: {
                            Button("新建习惯") { editor = HabitEditorTarget(habitId: nil) }
                        }
                    }
                }
                ForEach(groups, id: \.section) { group in
                    Section {
                        ForEach(group.habits) { h in
                            row(h)
                        }
                    } header: {
                        Text(group.section.name).uiDefaultFont(.subheadline, weight: .semibold)
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset(alternatesRowBackgrounds: false))
            // A column down the middle of a wide window, as the habit's
            // own page: across the whole width a habit's name and its
            // tick were a window apart.
            .frame(maxWidth: 640 * s)
            .frame(maxWidth: .infinity)
            #endif
            .navigationTitle(selected == today ? "习惯" : dayText(selected, today: today))
            .efficiencyTitleMenu()
            .toolbar {
                ToolbarItem(placement: .moreActions) {
                    Button("全部习惯", systemImage: "list.bullet") { showingAll = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("新建习惯", systemImage: "plus") { editor = HabitEditorTarget(habitId: nil) }
                }
            }
            .navigationDestination(for: String.self) { id in
                if let h = habits.first(where: { $0.id == id }) {
                    HabitDetailView(
                        habit: h, checkins: checkins, today: today,
                        onSaveHabit: onSaveHabit, onSaveCheckin: onSaveCheckin,
                        onEdit: { editor = HabitEditorTarget(habitId: id) },
                        onDeleted: { path.removeAll() },
                        clock: clock
                    )
                } else {
                    ContentUnavailableView("习惯已删除", systemImage: "leaf")
                }
            }
        }
        .sheet(item: $editor) { target in
            HabitEditorView(
                habit: target.habitId.flatMap { id in habits.first { $0.id == id } },
                today: today,
                onSave: { draft, base in
                    onSaveHabit(draft.habit(base: base, newId: newId(), now: clock()))
                }
            )
        }
        .sheet(isPresented: $showingAll) {
            HabitListView(habits: live, today: today, onSaveHabit: onSaveHabit, newId: newId, clock: clock)
        }
        .amountPrompt($amount, onSave: onSaveCheckin, clock: clock)
    }

    private func row(_ h: Habit) -> some View {
        let c = checkinOn(h, selected, checkins)
        let state = dayState(h, on: selected, checkin: c, today: today)
        return NavigationLink(value: h.id) {
            HabitRow(
                habit: h, state: state,
                subtitle: habitSubtitle(h, state: state, checkin: c, streak: streak(h, checkins: checkins, today: today)),
                onTap: { onSaveCheckin(habitTap(h, on: selected, existing: c, now: clock())) }
            )
        }
        .contextMenu {
            HabitDayMenu(habit: h, day: selected, existing: c, onSave: onSaveCheckin, clock: clock) {
                amount = AmountPrompt(habit: h, day: selected, existing: c)
            }
            Divider()
            Button("编辑", systemImage: "pencil") { editor = HabitEditorTarget(habitId: h.id) }
        }
        .swipeActions(edge: .trailing) {
            if let c {
                Button("取消打卡", systemImage: "arrow.uturn.backward") { onSaveCheckin(removedCheckin(c, now: clock())) }
            }
        }
        .swipeActions(edge: .leading) {
            if c?.status != .abandoned {
                Button("放弃", systemImage: "xmark") { onSaveCheckin(abandonDay(h, on: selected, existing: c, now: clock())) }
                    .tint(.gray)
            }
        }
    }
}

struct HabitEditorTarget: Identifiable, Hashable {
    var habitId: String?
    var id: String { habitId ?? "new" }
}

// MARK: - Row

struct HabitRow: View {
    @Environment(\.uiScale) private var s
    var habit: Habit
    var state: HabitDayState
    var subtitle: String
    var onTap: () -> Void

    var body: some View {
        HStack(spacing: 12 * s) {
            EmojiBadge(emoji: habit.emoji, color: habit.color, fallback: "leaf.fill", size: 38)
            VStack(alignment: .leading, spacing: 2 * s) {
                Text(habit.name)
                    // A navigation link's label has a font of its own.
                    .uiFont(.body)
                    .strikethrough(state == .abandoned, color: .secondary)
                Text(subtitle)
                    .uiFont(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            CheckButton(habit: habit, state: state, action: onTap)
        }
        .padding(.vertical, 2 * s)
    }
}

/// The round button on a habit's row: a tick for a single check-in, a ring
/// filling up (with a plus) for a count.
struct CheckButton: View {
    @Environment(\.uiScale) private var s
    var habit: Habit
    var state: HabitDayState
    var action: () -> Void

    private var tint: Color { EfficiencyPalette.color(habit.color) }

    private var progress: Double {
        switch state {
        case .done: 1
        case .partial(let p): p
        default: 0
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .uiFont(size: 28)
                        .foregroundStyle(.white, tint)
                case .abandoned:
                    Image(systemName: "xmark.circle.fill")
                        .uiFont(size: 28)
                        .foregroundStyle(.white, Color.secondary.opacity(0.6))
                default:
                    Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 2)
                    if habit.goalKind == .count {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "plus")
                            .uiFont(size: 12, weight: .bold)
                            .foregroundStyle(tint)
                    }
                }
            }
            .frame(width: 28 * s, height: 28 * s)
            .contentShape(.circle)
            .animation(.snappy, value: progress)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(accessibilityText))
        .sensoryFeedback(.success, trigger: state == .done)
    }

    private var accessibilityText: String {
        switch state {
        case .done: "已完成，点按取消"
        case .abandoned: "已放弃，点按打卡"
        default: habit.goalKind == .count ? "加\(amountText(habit.step))\(habit.unit)" : "打卡"
        }
    }
}

/// What can be done to one habit on one day: the context menu of a row
/// and of a day on the detail page's calendar.
struct HabitDayMenu: View {
    var habit: Habit
    var day: Day
    var existing: HabitCheckin?
    var onSave: (HabitCheckin) -> Void
    var clock: () -> Int
    var askAmount: () -> Void

    var body: some View {
        if existing?.status != .done || habit.goalKind == .count {
            Button(habit.goalKind == .count ? "加\(amountText(habit.step))\(habit.unit)" : "打卡", systemImage: "checkmark") {
                onSave(checkIn(habit, on: day, existing: existing, now: clock()))
            }
        }
        if habit.goalKind == .count {
            Button("输入数量…", systemImage: "number", action: askAmount)
        }
        if existing?.status != .abandoned {
            Button("放弃这天", systemImage: "xmark") {
                onSave(abandonDay(habit, on: day, existing: existing, now: clock()))
            }
        }
        if let existing {
            Button("取消打卡", systemImage: "arrow.uturn.backward", role: .destructive) {
                onSave(removedCheckin(existing, now: clock()))
            }
        }
    }
}

// MARK: - Amount

/// The habit and day whose amount is being typed in.
struct AmountPrompt: Identifiable {
    var habit: Habit
    var day: Day
    var existing: HabitCheckin?
    var id: String { HabitCheckin.id(habitId: habit.id, day: day) }
}

private struct AmountPromptModifier: ViewModifier {
    @Binding var prompt: AmountPrompt?
    var onSave: (HabitCheckin) -> Void
    var clock: () -> Int
    @State private var text = ""

    func body(content: Content) -> some View {
        content.alert(
            "输入数量",
            isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
            presenting: prompt
        ) { p in
            TextField(p.habit.unit.isEmpty ? "数量" : p.habit.unit, text: $text)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Button("确定") {
                if let v = Double(text.trimmingCharacters(in: .whitespaces)) {
                    onSave(setCheckinValue(p.habit, on: p.day, existing: p.existing, value: v, now: clock()))
                }
                text = ""
            }
            Button("取消", role: .cancel) { text = "" }
        } message: { p in
            Text("\(dayText(p.day))，目标\(amountText(p.habit.goal))\(p.habit.unit)")
        }
        .onChange(of: prompt?.id) {
            text = prompt.map { amountText($0.existing?.value ?? 0) } ?? ""
        }
    }
}

extension View {
    func amountPrompt(_ prompt: Binding<AmountPrompt?>, onSave: @escaping (HabitCheckin) -> Void, clock: @escaping () -> Int) -> some View {
        modifier(AmountPromptModifier(prompt: prompt, onSave: onSave, clock: clock))
    }
}

// MARK: - Week strip

/// The last seven days, each with a ring of how many of its habits were
/// done; tap one to check in on it.
struct WeekStrip: View {
    @Environment(\.uiScale) private var s
    var days: [Day]
    var today: Day
    @Binding var selected: Day
    var completion: (Day) -> (done: Int, due: Int)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { d in
                let (done, due) = completion(d)
                Button {
                    selected = d
                } label: {
                    VStack(spacing: 6 * s) {
                        Text(d == today ? "今" : weekdayLetter(d))
                            .uiFont(.caption2)
                            .foregroundStyle(d == today ? Color.accentColor : .secondary)
                        ZStack {
                            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: due == 0 ? 0 : Double(done) / Double(due))
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            if d == selected {
                                Circle().fill(Color.accentColor).padding(5 * s)
                            }
                            Text("\(d.day)")
                                .uiFont(.subheadline, weight: d == selected ? .semibold : .regular)
                                .monospacedDigit()
                                .foregroundStyle(d == selected ? Color.white : .primary)
                        }
                        .frame(width: 38 * s, height: 38 * s)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(dayText(d))，完成\(done)/\(due)"))
                .accessibilityAddTraits(d == selected ? .isSelected : [])
            }
        }
    }
}
