// The calendar's lists: the agenda (the month's days that have something
// on, from today in the current month) and the day under the phone's small
// month. Ports of `agenda_view.dart` and `month_view.dart`'s `DayTaskList`.

import OpenTodoDomain
import SwiftUI

/// A task in a calendar list: time, checkbox, title, list. A later date
/// of a repeating task is faded with a repeat mark.
struct EntryRow: View {
    let entry: CalendarEntry
    let ctx: CalendarContext
    let order: [String]
    var showsTimeColumn = true

    var body: some View {
        let task = entry.task
        let tint = ctx.color(of: task)
        let overdue = !entry.projected && !entry.done && isOverdue(task, ctx.now)
        let faded = entry.done || entry.projected
        HStack(spacing: 10) {
            if showsTimeColumn {
                VStack(alignment: .leading, spacing: 0) {
                    if let t = entry.time {
                        Text(clockLabel(t))
                        if let end = entry.endTime { Text(clockLabel(end)).foregroundStyle(.tertiary) }
                    } else {
                        Text("全天")
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(overdue ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                .frame(width: 44, alignment: .leading)
            }
            RoundedRectangle(cornerRadius: 1.5).fill(tint.opacity(faded ? 0.4 : 1)).frame(width: 3, height: 22)
            if entry.projected {
                Image(systemName: "repeat")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityLabel("重复")
            } else {
                PriorityCheckbox(checked: entry.done, priority: task.priority, size: 18) {
                    ctx.actions.setDone(task.id, !entry.done)
                }
            }
            Text(task.title.isEmpty ? "无标题" : task.title)
                .foregroundStyle(faded ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .strikethrough(entry.done)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !showsTimeColumn, let t = entry.time {
                Text(timeLabel(t))
                    .font(.caption)
                    .foregroundStyle(overdue ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
            }
            Text(ctx.listName(task.listId))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .listRowBackground(ctx.isSelected(entry) ? tint.opacity(0.18) : nil)
        .modifier(ChipInteractions(entry: entry, ctx: ctx, order: order))
    }
}

/// The month's days that have something on, one under another. In the
/// current month it starts at today: the agenda looks ahead.
struct AgendaView: View {
    let ctx: CalendarContext
    let range: DayRange

    var body: some View {
        let entries = ctx.entries(range)
        let from = agendaFrom(range, ctx.today)
        let shown = entries.filter { $0.date >= from }
        let order = calendarOrder(entries, mode: .agenda, range: range, today: ctx.today)
        let byDay = entriesByDay(shown)
        let days = byDay.keys.sorted()
        if days.isEmpty {
            ContentUnavailableView("这段时间没有安排", systemImage: "calendar.badge.checkmark",
                                   description: Text(verbatim: "\(range.start.year)年\(range.start.month)月\(from > range.start ? "接下来" : "")没有任务"))
        } else {
            List {
                ForEach(days, id: \.self) { day in
                    Section {
                        ForEach(byDay[day] ?? [], id: \.key) { e in
                            EntryRow(entry: e, ctx: ctx, order: order)
                        }
                    } header: {
                        Button {
                            ctx.model.showDay(day)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(verbatim: "\(day.day)")
                                    .font(.title3.weight(.semibold))
                                    .monospacedDigit()
                                Text(daySectionTitle(day, today: ctx.today))
                                    .font(.subheadline)
                                if ctx.model.prefs.showLunar {
                                    CalendarDayNote(date: day, font: .caption)
                                }
                            }
                            .foregroundStyle(day == ctx.today ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.insetGrouped)
            #endif
        }
    }
}

/// One day's tasks as list rows, under a heading.
struct DayTaskList: View {
    let ctx: CalendarContext
    let day: Day
    let entries: [CalendarEntry]

    var body: some View {
        let order = entryOrder(entries)
        List {
            Section {
                if entries.isEmpty {
                    ContentUnavailableView("这天没有任务", systemImage: "calendar")
                        .listRowBackground(Color.clear)
                }
                ForEach(entries, id: \.key) { e in
                    EntryRow(entry: e, ctx: ctx, order: order, showsTimeColumn: false)
                }
            } header: {
                HStack(spacing: 6) {
                    Text(daySectionTitle(day, today: ctx.today))
                    if ctx.model.prefs.showLunar { CalendarDayNote(date: day, font: .caption) }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }
}
