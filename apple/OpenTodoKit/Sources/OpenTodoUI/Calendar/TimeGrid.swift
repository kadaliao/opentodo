// Days side by side over the hours: the day, 3-day and week views. Each
// day has a heading (weekday, number, lunar note); tasks without a time sit
// in the all-day row on top (a span one bar across its days); the hours
// scroll below, opening two hours before now. Timed tasks are as tall as
// they are long, side by side where they overlap (`layoutTimed`), a span
// past midnight cut at each day's end. Today has the red line of now.
// Tasks drag to another day or time (snapping to 15 minutes) or into the
// all-day row, and their bottom edge drags to set when they end; a click
// on an empty hour starts a task at that half hour. Port of
// `time_grid.dart`.

import OpenTodoDomain
import SwiftUI

struct TimeGrid: View {
    @Environment(\.uiScale) private var s
    let ctx: CalendarContext
    let range: DayRange


    /// The hours' column, at 标准 (it grows with 界面大小; the hour's height
    /// doesn't).
    static let gutter: CGFloat = 52
    private static let gridSpace = "calendar-grid"
    private static let allDaySpace = "calendar-all-day"

    var body: some View {
        let entries = ctx.entries(range)
        let order = calendarOrder(entries, mode: ctx.model.mode, range: range, today: ctx.today)
        let byDay = entriesByDay(entries)
        let days = range.days
        VStack(spacing: 0) {
            headings(days)
            allDayRow(days, entries: entries.filter(\.allDay), order: order)
            Divider()
            ScrollViewReader { proxy in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    HourGutter(nowMinute: days.contains(ctx.today) ? ctx.now.minuteOfDay : nil)
                        .frame(width: Self.gutter * s)
                    GeometryReader { geo in
                        let width = geo.size.width / CGFloat(days.count)
                        HStack(spacing: 0) {
                            ForEach(days, id: \.self) { day in
                                DayColumn(
                                    ctx: ctx, day: day, placements: layoutTimed(byDay[day] ?? []),
                                    order: order, width: width
                                )
                                .frame(width: width)
                            }
                        }
                        .coordinateSpace(name: Self.gridSpace)
                        .calendarDropTarget(CalendarDropDelegate(ctx: ctx, space: Self.gridSpace) { point, drag in
                            let i = Int(point.x / width)
                            guard days.indices.contains(i) else { return nil }
                            let lead = drag.lead
                            let fromHere = drag.origin == Self.gridSpace
                            let minute = CalendarLogic.dropMinute(
                                pointerY: point.y,
                                startPointerY: fromHere ? drag.start?.y : nil,
                                barTop: fromHere ? lead?.time.map(CalendarLogic.gridY) : nil
                            )
                            return .grid(days[i], minute: minute, length: lead.map(Self.length) ?? 30)
                        })
                    }
                    .frame(height: CalendarLogic.gridY(minutesPerDay))
                }
                .background(alignment: .top) {
                    // A mark at each hour, to scroll to; a little above the
                    // hour's line, so its label (centred on the line) isn't
                    // cut off under the all-day row.
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { h in
                            Color.clear.frame(height: CalendarMetrics.hourHeight).id(h)
                        }
                    }
                    .padding(.top, -10 * s)
                }
            }
            .onAppear {
                let hour = CalendarLogic.initialScrollMinute(range: range, now: ctx.now) / 60
                DispatchQueue.main.async { proxy.scrollTo(hour, anchor: .top) }
            }
            }
        }
    }

    /// How much of a dragged entry shows where it would land: a span's
    /// length, half an hour for the rest.
    static func length(_ e: CalendarEntry) -> Int {
        guard let time = e.time, let end = e.endTime else { return 30 }
        return end - time
    }

    private func headings(_ days: [Day]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutter * s)
            ForEach(days, id: \.self) { day in
                let isToday = day == ctx.today
                Button {
                    ctx.model.showDay(day)
                } label: {
                    // Narrow columns (a week on a phone): the weekday over
                    // the number, without the lunar note, which ran into
                    // the next day's heading.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5 * s) {
                            weekday(day, isToday: isToday)
                            CalendarDayNumber(text: "\(day.day)", isToday: isToday, size: 14)
                            if ctx.model.prefs.showLunar {
                                CalendarDayNote(date: day)
                            }
                        }
                        .fixedSize()
                        VStack(spacing: 1 * s) {
                            weekday(day, isToday: isToday)
                            CalendarDayNumber(text: "\(day.day)", isToday: isToday, size: 14)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(days.count > 1)
                .accessibilityLabel(daySectionTitle(day, today: ctx.today))
            }
        }
        .frame(height: 40 * s)
    }

    private func weekday(_ day: Day, isToday: Bool) -> some View {
        Text(weekdayName(day))
            .uiFont(size: 12)
            .foregroundStyle(isToday ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
            .lineLimit(1)
    }

    private func allDayRow(_ days: [Day], entries: [CalendarEntry], order: [String]) -> some View {
        let items = weekLayout(entries, week: range)
        let needed = (items.map(\.line).max() ?? -1) + 1
        let room = CalendarLogic.allDayLines(busiest: needed, days: days.count)
        let fit = CalendarLogic.monthRowFit(items, room: room, days: days.count)
        let line = (CalendarMetrics.chipHeight + CalendarMetrics.chipGap) * s
        let height = CGFloat(max(room, 1)) * line + 6 * s
        return HStack(spacing: 0) {
            Text("全天")
                .uiFont(size: 11)
                .foregroundStyle(.secondary)
                .frame(width: (Self.gutter - 8) * s, alignment: .trailing)
                .padding(.trailing, 8 * s)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 5 * s)
            GeometryReader { geo in
                let width = geo.size.width / CGFloat(days.count)
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            let hovered = ctx.model.hover?.target == .allDay(day)
                            Rectangle()
                                .fill(hovered ? Palette.accent.opacity(0.14) : Color.clear)
                                .overlay(alignment: .leading) { Rectangle().fill(.separator).frame(width: 0.5) }
                                .contentShape(Rectangle())
                                .onTapGesture { ctx.tapEmpty(day, time: nil, place: .cell(day)) }
                                .calendarNewTaskPopover(ctx, place: .cell(day))
                                .frame(width: width)
                        }
                    }
                    ForEach(items.filter { $0.line < fit.lines }, id: \.entry.key) { item in
                        EntryBar(entry: item.entry, ctx: ctx, order: order, showTime: false,
                                 openStart: item.continuesBefore, openEnd: item.continuesAfter)
                            .frame(width: CGFloat(item.columns) * width - 4)
                            .offset(x: CGFloat(item.column) * width + 2, y: 3 * s + CGFloat(item.line) * line)
                    }
                    ForEach(Array(fit.hidden.enumerated()).filter { $0.element > 0 }, id: \.offset) { column, count in
                        CalendarMoreButton(count: count) { ctx.model.showDay(days[column]) }
                            .frame(width: width - 4)
                            .offset(x: CGFloat(column) * width + 2, y: 3 * s + CGFloat(fit.lines) * line)
                    }
                }
                .coordinateSpace(name: Self.allDaySpace)
                .calendarDropTarget(CalendarDropDelegate(ctx: ctx, space: Self.allDaySpace) { point, _ in
                    let i = Int(point.x / width)
                    return days.indices.contains(i) ? .allDay(days[i]) : nil
                })
            }
        }
        .frame(height: height)
    }
}

/// The hours down the left; now in red beside today's line.
private struct HourGutter: View {
    @Environment(\.uiScale) private var s
    let nowMinute: Int?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(1..<24, id: \.self) { h in
                // Left out where the red time of now would sit over it.
                if nowMinute.map({ CGFloat(abs($0 - h * 60)) >= 12 * s }) ?? true {
                    Text(clockLabel(h * 60))
                        .uiFont(size: 10)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .offset(y: CalendarLogic.gridY(h * 60) - 7 * s)
                }
            }
            if let nowMinute {
                Text(clockLabel(nowMinute))
                    .uiFont(size: 10, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(.red)
                    .offset(y: CalendarLogic.gridY(nowMinute) - 7 * s)
            }
        }
        .padding(.trailing, 8 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .frame(height: CalendarLogic.gridY(minutesPerDay))
    }
}

/// One day over the hours.
private struct DayColumn: View {
    @Environment(\.uiScale) private var s
    let ctx: CalendarContext
    let day: Day
    let placements: [TimedPlacement]
    let order: [String]
    let width: CGFloat

    var body: some View {
        let model = ctx.model
        let isToday = day == ctx.today
        let fullHeight = CalendarLogic.gridY(minutesPerDay)
        ZStack(alignment: .topLeading) {
            // The hour lines, and the space that starts a task.
            Canvas { context, size in
                var path = Path()
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: 0, y: size.height))
                for h in 1..<24 {
                    let y = CalendarLogic.gridY(h * 60)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
            }
            .background(isToday ? Palette.accent.opacity(0.04) : Color.clear)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                let minute = CalendarLogic.gridMinute(atY: tap.location.y, step: 30)
                ctx.tapEmpty(day, time: minute, place: .grid(day, minute))
            })
            .modifier(GridNewTaskAnchor(ctx: ctx, day: day, width: width))

            ForEach(placements, id: \.entry.key) { p in
                block(p, fullHeight: fullHeight)
            }

            if case .grid(let hoverDay, let minute, let length)? = model.hover?.target, hoverDay == day {
                let top = CalendarLogic.gridY(minute)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Palette.accent.opacity(0.14))
                    .strokeBorder(Palette.accent, lineWidth: 1)
                    .overlay(alignment: .topLeading) {
                        Text(CalendarLogic.hoverLabel(minute: minute, count: model.hover?.count ?? 1))
                            .uiFont(size: 10, weight: .semibold)
                            .foregroundStyle(Palette.accent)
                            .padding(.leading, 4 * s)
                            .padding(.top, 2 * s)
                    }
                    .frame(width: width - 3, height: CalendarLogic.gridY(min(length, minutesPerDay - minute)))
                    .offset(x: 1, y: top)
                    .allowsHitTesting(false)
            }

            if isToday {
                let y = CalendarLogic.gridY(ctx.now.minuteOfDay)
                HStack(spacing: 0) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Rectangle().fill(.red).frame(height: 1.5)
                }
                .frame(width: width + 4)
                .offset(x: -4, y: y - 4)
                .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: fullHeight, alignment: .topLeading)
    }

    @ViewBuilder private func block(_ p: TimedPlacement, fullHeight: CGFloat) -> some View {
        let resizing = ctx.model.resize.flatMap { $0.key == p.entry.key ? $0.end : nil }
        let end = resizing ?? p.end
        let height = max(CalendarLogic.gridY(end - p.start), CalendarMetrics.chipHeight * s) - 1
        let w = width / CGFloat(p.columns) - 3
        // A task late at night stays inside the day.
        let top = min(CalendarLogic.gridY(p.start), fullHeight - height - 1)
        let left = width * CGFloat(p.column) / CGFloat(p.columns) + 1
        TimedBlock(placement: p, ctx: ctx, order: order, height: height, resizingTo: resizing)
            .frame(width: w, height: height)
            .offset(x: left, y: top)
        // The bottom edge sets the end; a span that runs on into the next
        // day ends there, not here.
        if CalendarLogic.canMoveEntry(p.entry) && (p.entry.endTime ?? 0) < minutesPerDay {
            ResizeHandle(placement: p, ctx: ctx)
                .frame(width: w)
                .offset(x: left, y: top + height - 5)
        }
    }
}

/// Points a new task's popover at the half hour that was clicked.
private struct GridNewTaskAnchor: ViewModifier {
    let ctx: CalendarContext
    let day: Day
    let width: CGFloat

    func body(content: Content) -> some View {
        if case .grid(let d, let minute)? = ctx.model.newTask?.place, d == day {
            content.calendarNewTaskPopover(
                ctx, place: .grid(d, minute),
                anchor: CGRect(x: 0, y: CalendarLogic.gridY(minute), width: width, height: CalendarLogic.gridY(30))
            )
        } else {
            content
        }
    }
}
