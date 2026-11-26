// One habit: its numbers (current and longest streak, check-ins, this
// month's rate), a month calendar where any past day can be checked in or
// taken back, and a heat map of the last weeks.

import OpenTodoDomain
import SwiftUI

struct HabitDetailView: View {
    var habit: Habit
    var checkins: [HabitCheckin]
    var today: Day
    var onSaveHabit: (Habit) -> Void
    var onSaveCheckin: (HabitCheckin) -> Void
    var onEdit: () -> Void
    var onDeleted: () -> Void
    var clock: () -> Int

    @State private var month: Day
    @State private var amount: AmountPrompt?
    @State private var confirmingDelete = false

    init(
        habit: Habit, checkins: [HabitCheckin], today: Day,
        onSaveHabit: @escaping (Habit) -> Void, onSaveCheckin: @escaping (HabitCheckin) -> Void,
        onEdit: @escaping () -> Void, onDeleted: @escaping () -> Void, clock: @escaping () -> Int
    ) {
        self.habit = habit
        self.checkins = checkins
        self.today = today
        self.onSaveHabit = onSaveHabit
        self.onSaveCheckin = onSaveCheckin
        self.onEdit = onEdit
        self.onDeleted = onDeleted
        self.clock = clock
        _month = State(initialValue: today.startOfMonth)
    }

    private var tint: Color { EfficiencyPalette.color(habit.color) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                stats
                calendar
                heatmap
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
        .navigationTitle(habit.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("更多", systemImage: "ellipsis.circle") {
                    Button("编辑", systemImage: "pencil", action: onEdit)
                    Button(habit.archivedAt == nil ? "归档" : "恢复", systemImage: habit.archivedAt == nil ? "archivebox" : "arrow.uturn.backward") {
                        var h = habit
                        h.archivedAt = habit.archivedAt == nil ? clock() : nil
                        h.updatedAt = clock()
                        h.dirty = true
                        onSaveHabit(h)
                    }
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .confirmationDialog("删除“\(habit.name)”？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除习惯和打卡记录", role: .destructive) {
                onSaveHabit(deletedHabit(habit, now: clock()))
                onDeleted()
            }
        } message: {
            Text("只想暂时不打卡的话，可以归档。")
        }
        .amountPrompt($amount, onSave: onSaveCheckin, clock: clock)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 14) {
            EmojiBadge(emoji: habit.emoji, color: habit.color, fallback: "leaf.fill", size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name).font(.title2.bold())
                Text("\(frequencyText(habit.frequency)) · \(goalText(habit)) · \(dayText(habit.startDate, today: today))开始")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if habit.archivedAt != nil {
                    Label("已归档", systemImage: "archivebox").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .panel()
    }

    private var stats: some View {
        let s = streak(habit, checkins: checkins, today: today)
        let unit = s.unit == .weeks ? "周" : "天"
        let rate = monthCompletionRate(habit, checkins: checkins, year: today.year, month: today.month, today: today)
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(title: "当前连续", value: "\(s.current)", unit: unit, symbol: "flame.fill", tint: .orange)
                StatTile(title: "最长连续", value: "\(s.longest)", unit: unit, symbol: "trophy.fill", tint: .yellow)
            }
            GridRow {
                StatTile(title: "总打卡", value: "\(totalCheckins(habit, checkins: checkins))", unit: "天", symbol: "checkmark.seal.fill", tint: tint)
                StatTile(title: "本月完成率", value: rate.map { "\(Int(($0 * 100).rounded()))" } ?? "–", unit: rate == nil ? "" : "%", symbol: "chart.pie.fill", tint: .blue)
            }
        }
    }

    private var calendar: some View {
        let byDay = Dictionary(
            checkins.filter { $0.habitId == habit.id && $0.deletedAt == nil }.map { ($0.day, $0) },
            uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b }
        )
        return VStack(spacing: 10) {
            HStack {
                Text("\(String(month.year))年\(month.month)月").font(.headline)
                Spacer()
                Button("上个月", systemImage: "chevron.left") { month = month.addingMonths(-1) }
                Button("下个月", systemImage: "chevron.right") { month = month.addingMonths(1) }
                    .disabled(month >= today.startOfMonth)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            HStack(spacing: 0) {
                ForEach(weekdayNames, id: \.self) { n in
                    Text(String(n.dropFirst())).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            Grid(horizontalSpacing: 0, verticalSpacing: 6) {
                ForEach(Array(monthGrid(year: month.year, month: month.month).enumerated()), id: \.offset) { _, week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { i in
                            if let d = week[i] {
                                dayCell(d, byDay[d])
                            } else {
                                Color.clear.frame(height: 36)
                            }
                        }
                    }
                }
            }
        }
        .panel()
    }

    @ViewBuilder
    private func dayCell(_ d: Day, _ c: HabitCheckin?) -> some View {
        let state = dayState(habit, on: d, checkin: c, today: today)
        let cell = HabitDayCell(day: d, state: state, isToday: d == today, tint: tint).frame(maxWidth: .infinity)
        if d <= today {
            Menu {
                Text(dayText(d, today: today))
                HabitDayMenu(habit: habit, day: d, existing: c, onSave: onSaveCheckin, clock: clock) {
                    amount = AmountPrompt(habit: habit, day: d, existing: c)
                }
            } label: {
                cell
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        } else {
            cell
        }
    }

    private var heatmap: some View {
        let weeks = heatmapWeeks(endingOn: today, weeks: 20)
        let log = Dictionary(
            checkins.filter { $0.habitId == habit.id && $0.deletedAt == nil }.map { ($0.day, $0) },
            uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b }
        )
        return VStack(alignment: .leading, spacing: 10) {
            Text("最近20周").font(.headline)
            ViewThatFits(in: .horizontal) {
                heatmapGrid(weeks, log, size: 14)
                heatmapGrid(Array(weeks.suffix(14)), log, size: 14)
                heatmapGrid(Array(weeks.suffix(10)), log, size: 14)
            }
            HStack(spacing: 12) {
                legend(tint, "完成")
                legend(tint.opacity(0.4), "部分")
                legend(Color.secondary.opacity(0.15), "未打卡")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func heatmapGrid(_ weeks: [[Day]], _ log: [Day: HabitCheckin], size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(weeks, id: \.first) { week in
                VStack(spacing: 3) {
                    ForEach(week, id: \.self) { d in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(heatColor(dayState(habit, on: d, checkin: log[d], today: today)))
                            .frame(width: size, height: size)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("最近\(weeks.count)周的打卡"))
    }

    private func heatColor(_ s: HabitDayState) -> Color {
        switch s {
        case .done: tint
        case .partial(let p): tint.opacity(0.25 + 0.4 * p)
        case .abandoned: Color.secondary.opacity(0.35)
        case .future: .clear
        case .beforeStart: Color.secondary.opacity(0.06)
        default: Color.secondary.opacity(0.15)
        }
    }

    private func legend(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 10, height: 10)
            Text(text)
        }
    }
}

/// The habit with its tombstone set.
func deletedHabit(_ h: Habit, now: Int) -> Habit {
    var h = h
    h.deletedAt = now
    h.updatedAt = now
    h.dirty = true
    return h
}

/// A day on the habit's month calendar.
struct HabitDayCell: View {
    var day: Day
    var state: HabitDayState
    var isToday: Bool
    var tint: Color

    var body: some View {
        ZStack {
            switch state {
            case .done:
                Circle().fill(tint)
            case .partial(let p):
                Circle().stroke(tint.opacity(0.2), lineWidth: 3)
                Circle().trim(from: 0, to: p).stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            case .abandoned:
                Circle().fill(Color.secondary.opacity(0.18))
            case .missed:
                Circle().strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            default:
                EmptyView()
            }
            if isToday && state != .done {
                Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
            Text("\(day.day)")
                .font(.callout.weight(isToday ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(foreground)
            if state == .abandoned {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary).offset(y: 11)
            }
        }
        .frame(width: 34, height: 34)
        .contentShape(.circle)
        .accessibilityElement()
        .accessibilityLabel(Text("\(dayText(day))，\(stateName)"))
    }

    private var foreground: Color {
        switch state {
        case .done: .white
        case .future, .beforeStart, .notDue: Color.secondary.opacity(0.6)
        default: .primary
        }
    }

    private var stateName: String {
        switch state {
        case .done: "已完成"
        case .partial: "部分完成"
        case .abandoned: "已放弃"
        case .missed: "未打卡"
        case .pending: "待打卡"
        case .notDue: "不用打卡"
        case .beforeStart: "还没开始"
        case .future: "未到"
        }
    }
}

/// A number with its label: the habit and focus statistics.
struct StatTile: View {
    var title: String
    var value: String
    var unit: String
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(TintedIconLabelStyle(tint: tint))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title.bold()).monospacedDigit()
                Text(unit).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

struct TintedIconLabelStyle: LabelStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}
