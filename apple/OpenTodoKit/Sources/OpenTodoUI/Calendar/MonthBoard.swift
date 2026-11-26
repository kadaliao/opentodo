// The month as a board of days (and the multi-week view, the same rows for
// 2–6 weeks): each week a row of cells with the day's number and lunar
// note, its tasks as bars on top, a task over several days one bar across
// them (`weekLayout`), and "+N" where a day has more than fits. Tasks drag
// between days; a click on a day's empty space starts a task there. Port of
// `month_view.dart`'s `MonthBoard`.

import OpenTodoDomain
import SwiftUI

struct MonthBoard: View {
    @Environment(\.uiScale) private var s
    let ctx: CalendarContext
    let range: DayRange
    /// The month on show, whose days are drawn brighter; nil for the
    /// multi-week view, where every day counts.
    let month: (year: Int, month: Int)?

    private static let space = "calendar-month"

    var body: some View {
        let entries = ctx.entries(range)
        let order = calendarOrder(entries, mode: ctx.model.mode, range: range, today: ctx.today)
        let rows = weekRows(range)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdayNames, id: \.self) { name in
                    Text(name)
                        .uiFont(size: 11, weight: .medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 24 * s)
            Divider()
            GeometryReader { geo in
                let rowHeight = geo.size.height / CGFloat(max(rows.count, 1))
                let columnWidth = geo.size.width / 7
                VStack(spacing: 0) {
                    ForEach(rows, id: \.start) { week in
                        WeekRow(
                            ctx: ctx, week: week, entries: entries, order: order, month: month,
                            columnWidth: columnWidth, height: rowHeight
                        )
                    }
                }
                .coordinateSpace(name: Self.space)
                .calendarDropTarget(CalendarDropDelegate(ctx: ctx, space: Self.space) { point, _ in
                    let r = Int(point.y / rowHeight), c = Int(point.x / columnWidth)
                    guard rows.indices.contains(r), (0..<7).contains(c) else { return nil }
                    let day = rows[r].start + c
                    return rows[r].contains(day) ? .cell(day) : nil
                })
            }
        }
    }
}

/// One week of the board.
private struct WeekRow: View {
    let ctx: CalendarContext
    let week: DayRange
    let entries: [CalendarEntry]
    let order: [String]
    let month: (year: Int, month: Int)?
    let columnWidth: CGFloat
    let height: CGFloat
    @Environment(\.uiScale) private var s

    var body: some View {
        let items = weekLayout(entries, week: week)
        let fit = CalendarLogic.monthRowFit(items, room: CalendarLogic.cellLines(height: height, scale: s))
        let line = (CalendarMetrics.chipHeight + CalendarMetrics.chipGap) * s
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(week.days, id: \.self) { day in
                    DayCell(ctx: ctx, day: day, inMonth: month.map { day.year == $0.year && day.month == $0.month } ?? true)
                        .frame(width: columnWidth, height: height)
                }
            }
            ForEach(items.filter { $0.line < fit.lines }, id: \.entry.key) { item in
                EntryBar(
                    entry: item.entry, ctx: ctx, order: order,
                    showTime: !item.isBar && columnWidth >= 120 * s,
                    openStart: item.continuesBefore, openEnd: item.continuesAfter
                )
                .frame(width: CGFloat(item.columns) * columnWidth - (item.continuesBefore ? 0 : 3) - (item.continuesAfter ? 0 : 3))
                .offset(
                    x: CGFloat(item.column) * columnWidth + (item.continuesBefore ? 0 : 3),
                    y: CalendarMetrics.cellHeader * s + CGFloat(item.line) * line
                )
            }
            ForEach(Array(fit.hidden.enumerated()).filter { $0.element > 0 }, id: \.offset) { column, count in
                CalendarMoreButton(count: count) { ctx.model.showDay(week.start + column) }
                    .frame(width: columnWidth - 6)
                    .offset(x: CGFloat(column) * columnWidth + 3, y: CalendarMetrics.cellHeader * s + CGFloat(fit.lines) * line)
            }
        }
        .frame(height: height, alignment: .topLeading)
        .clipped()
    }
}

/// A day's cell: its number (today in a red disc, 11月1日 on the first),
/// the lunar note, and the empty space that starts a task.
private struct DayCell: View {
    let ctx: CalendarContext
    let day: Day
    let inMonth: Bool
    @Environment(\.uiScale) private var s

    @ViewBuilder private func headerRow(isToday: Bool, lunar: Bool) -> some View {
        if s > 1 {
            // Bigger than 标准 a narrow cell can't hold 11月1日 and the lunar
            // day: the plain number, and no lunar day rather than half of one.
            ViewThatFits(in: .horizontal) {
                header(label: CalendarLogic.cellDayLabel(day), lunar: lunar, isToday: isToday)
                header(label: "\(day.day)", lunar: lunar, isToday: isToday)
                header(label: "\(day.day)", lunar: false, isToday: isToday)
            }
        } else {
            HStack(spacing: 4 * s) {
                CalendarDayNumber(text: CalendarLogic.cellDayLabel(day), isToday: isToday, dim: !inMonth)
                if lunar {
                    CalendarDayNote(date: day, dim: !inMonth)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The number and the lunar day, whole (for `ViewThatFits`).
    private func header(label: String, lunar: Bool, isToday: Bool) -> some View {
        HStack(spacing: 4 * s) {
            CalendarDayNumber(text: label, isToday: isToday, dim: !inMonth)
            if lunar {
                CalendarDayNote(date: day, dim: !inMonth).fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        let model = ctx.model
        let isToday = day == ctx.today
        let hovered = model.hover?.target == .cell(day)
        VStack(alignment: .leading, spacing: 0) {
            headerRow(isToday: isToday, lunar: model.prefs.showLunar)
            .padding(.leading, 2 * s)
            .padding(.top, 2 * s)
            .frame(height: CalendarMetrics.cellHeader * s, alignment: .top)
            Spacer(minLength: 0)
        }
        .background {
            Rectangle().fill(
                hovered ? Palette.accent.opacity(0.14)
                    : isToday ? Palette.accent.opacity(0.05)
                    : inMonth ? Color.clear : Color.secondary.opacity(0.05)
            )
        }
        .overlay(alignment: .trailing) { Rectangle().fill(.separator).frame(width: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
        .contentShape(Rectangle())
        .onTapGesture { ctx.tapEmpty(day, time: nil, place: .cell(day)) }
        .calendarNewTaskPopover(ctx, place: .cell(day))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("新建任务")
    }
}
