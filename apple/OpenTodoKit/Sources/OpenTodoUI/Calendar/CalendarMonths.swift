// Small months: the date picker of the sidebar and of the phone's month
// view (days with tasks dotted), and the year view's twelve (each day
// shaded by how many tasks it has). Ports of `month_view.dart`'s
// `MiniMonth` and `PhoneMonth`; the year view is new.

import OpenTodoDomain
import SwiftUI

private let shortWeekdays = ["一", "二", "三", "四", "五", "六", "日"]

/// A small month of day numbers.
struct MiniMonth: View {
    enum Marks {
        /// A dot under the days with something on.
        case dots(Set<Day>)
        /// The day shaded by `densityLevel` of its count.
        case density([Day: Int])
    }

    let year: Int
    let month: Int
    var selected: Day?
    let today: Day
    let marks: Marks
    /// At 标准; both grow with 界面大小.
    var rowHeight: CGFloat = 32
    var fontSize: CGFloat = 13
    let onTap: (Day) -> Void
    @Environment(\.uiScale) private var s
    private var row: CGFloat { rowHeight * s }

    var body: some View {
        let days = monthGrid(year, month).days
        let weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<$0 + 7]) }
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(shortWeekdays, id: \.self) { d in
                    Text(d).uiFont(size: fontSize - 2).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                }
            }
            .frame(height: row * 0.7)
            ForEach(weeks, id: \.first) { week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in
                        cell(day).frame(maxWidth: .infinity)
                    }
                }
                .frame(height: row)
            }
        }
    }

    private func cell(_ day: Day) -> some View {
        let inMonth = day.month == month && day.year == year
        let isSelected = day == selected
        let isToday = day == today
        let size = min(rowHeight - 6, fontSize * 2) * s
        let shade: Double = {
            guard case .density(let counts) = marks, inMonth else { return 0 }
            return [0, 0.18, 0.35, 0.55, 0.8][densityLevel(counts[day] ?? 0)]
        }()
        let dotted: Bool = {
            if case .dots(let days) = marks { return days.contains(day) }
            return false
        }()
        return Button {
            onTap(day)
        } label: {
            VStack(spacing: 1 * s) {
                Text(verbatim: "\(day.day)")
                    .uiFont(size: fontSize, weight: isToday || isSelected ? .semibold : .regular)
                    .monospacedDigit()
                    .foregroundStyle(
                        isSelected ? AnyShapeStyle(Color.white)
                            : isToday ? AnyShapeStyle(Color.red)
                            : !inMonth ? AnyShapeStyle(.quaternary)
                            : shade > 0.5 ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)
                    )
                    .frame(width: size, height: size)
                    .background {
                        if isSelected {
                            Circle().fill(isToday ? Color.red : Color.primary)
                        } else if shade > 0 {
                            RoundedRectangle(cornerRadius: 4).fill(Palette.accent.opacity(shade))
                        }
                    }
                if case .dots = marks {
                    Circle()
                        .fill(dotted ? (inMonth ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary)) : AnyShapeStyle(Color.clear))
                        .frame(width: 4 * s, height: 4 * s)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.month)月\(day.day)日")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The phone's month: a small month to pick a day from, that day's tasks
/// below. Swiping the month sideways turns the page.
struct PhoneMonth: View {
    let ctx: CalendarContext

    var body: some View {
        let model = ctx.model
        let anchor = model.anchor
        let grid = monthGrid(anchor.year, anchor.month)
        let byDay = entriesByDay(ctx.entries(grid))
        VStack(spacing: 0) {
            MiniMonth(
                year: anchor.year, month: anchor.month, selected: anchor, today: ctx.today,
                marks: .dots(Set(byDay.keys)), rowHeight: 44, fontSize: 16
            ) { model.anchor = $0 }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .gesture(DragGesture(minimumDistance: 30).onEnded { g in
                    if abs(g.translation.width) > abs(g.translation.height), abs(g.translation.width) > 50 {
                        withAnimation(.snappy) { model.perform(.page(g.translation.width < 0 ? 1 : -1), today: ctx.today) }
                    }
                })
            Divider()
            DayTaskList(ctx: ctx, day: anchor, entries: byDay[anchor] ?? [])
        }
    }
}

/// Twelve small months, each day shaded by how many tasks it has. A day
/// opens in the day view.
struct YearView: View {
    @Environment(\.uiScale) private var s
    let ctx: CalendarContext

    var body: some View {
        let year = ctx.model.anchor.year
        let counts = dayDensity(ctx.entries(visibleRange(.year, ctx.model.anchor)))
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: (ctx.compact ? 150 : 200) * s), spacing: 24 * s, alignment: .top)], spacing: 24 * s) {
                ForEach(1...12, id: \.self) { m in
                    VStack(alignment: .leading, spacing: 6 * s) {
                        Text(verbatim: "\(m)月")
                            .uiFont(.headline)
                            .foregroundStyle(year == ctx.today.year && m == ctx.today.month ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                        MiniMonth(
                            year: year, month: m, selected: nil, today: ctx.today, marks: .density(counts),
                            rowHeight: ctx.compact ? 22 : 26, fontSize: ctx.compact ? 10 : 11
                        ) { ctx.model.showDay($0) }
                    }
                }
            }
            .padding(20 * s)
        }
    }
}
