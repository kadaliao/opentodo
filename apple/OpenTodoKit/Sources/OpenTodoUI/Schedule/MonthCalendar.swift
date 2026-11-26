// The month the date dialog picks from: drawn like the system's graphical
// date picker (month and arrows on top, the days in a grid, the chosen day
// in a filled circle, today in the accent colour), with the lunar day or a
// festival under each number and 休 / 班 from the holiday schedule.
// Weeks start on Monday, like the app's calendar (`monthGrid` in
// `app/lib/domain/calendar.dart`).

import OpenTodoDomain
import SwiftUI

/// What a day says under its number: a festival or the lunar day, and
/// whether the holiday schedule has it off (休, true) or worked (班, false).
/// `dayNote` in `app/lib/domain/calendar.dart`; kept here until the
/// calendar's domain port lands, then this should call that.
struct ScheduleDayNote: Hashable {
    let label: String
    let special: Bool
    let off: Bool?

    init(_ date: Day) {
        let festival: String? = lunarFestival(date) ?? {
            switch (date.month, date.day) {
            case (1, 1): "元旦"
            case (5, 1): "劳动节"
            case (10, 1): "国庆节"
            default: nil
            }
        }()
        let lunar = toLunar(date)
        label = festival ?? lunar.map(lunarCalendarLabel) ?? ""
        special = festival != nil
        off = holidayOn(date)?.off
    }
}

/// One month's grid: whole weeks from Monday, nil where a day belongs to
/// the month before or after.
struct MonthPage: Hashable {
    let year: Int
    let month: Int

    init(_ day: Day) {
        year = day.year
        month = day.month
    }

    init(year: Int, month: Int) {
        let first = Day(year, month, 1)
        self.year = first.year
        self.month = first.month
    }

    var first: Day { Day(year, month, 1) }

    func adding(months n: Int) -> MonthPage { MonthPage(year: year, month: month + n) }

    var weeks: [[Day?]] {
        let first = self.first
        let start = first.startOfWeek
        let end = first.endOfMonth.startOfWeek + 7
        return stride(from: 0, to: start.days(to: end), by: 7).map { w in
            (0..<7).map { i in
                let d = start + (w + i)
                return d.month == month ? d : nil
            }
        }
    }

    var title: String { "\(year)年\(month)月" }
}

struct MonthCalendar: View {
    @Environment(\.uiScale) private var s
    @Binding var selection: Day
    let today: Day
    @State private var page: MonthPage

    init(selection: Binding<Day>, today: Day) {
        _selection = selection
        self.today = today
        _page = State(initialValue: MonthPage(selection.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 6 * s) {
            header
            HStack(spacing: 0) {
                ForEach(CustomRepeatEditor.weekdayShort, id: \.self) { w in
                    Text(w)
                        .uiFont(.caption2, weight: .semibold)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: 2 * s) {
                ForEach(Array(page.weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            if let d = week[i] {
                                DayCell(day: d, selected: d == selection, today: d == today) {
                                    selection = d
                                }
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: Self.cellHeight * s)
                            }
                        }
                    }
                }
            }
            .gesture(swipe)
        }
        .onChange(of: selection) { _, d in
            // A quick date elsewhere in the dialog turns to its month.
            if MonthPage(d) != page { withAnimation(.snappy) { page = MonthPage(d) } }
        }
    }

    #if os(macOS)
    static let cellHeight: CGFloat = 36
    #else
    static let cellHeight: CGFloat = 44
    #endif

    private var header: some View {
        HStack(spacing: 4 * s) {
            Text(page.title)
                .uiFont(.headline)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                withAnimation(.snappy) { page = MonthPage(today) }
            } label: {
                Image(systemName: "circle")
                    .uiFont(size: 9, weight: .bold)
                    .frame(width: 24 * s, height: 28 * s)
            }
            .accessibilityLabel("本月")
            .disabled(page == MonthPage(today))
            Button {
                withAnimation(.snappy) { page = page.adding(months: -1) }
            } label: {
                Image(systemName: "chevron.left").frame(width: 28 * s, height: 28 * s)
            }
            .accessibilityLabel("上个月")
            Button {
                withAnimation(.snappy) { page = page.adding(months: 1) }
            } label: {
                Image(systemName: "chevron.right").frame(width: 28 * s, height: 28 * s)
            }
            .accessibilityLabel("下个月")
        }
        .uiFont(.body, weight: .semibold)
        .buttonStyle(.borderless)
        .tint(.accentColor)
        .padding(.leading, 4 * s)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height) else { return }
            withAnimation(.snappy) { page = page.adding(months: v.translation.width < 0 ? 1 : -1) }
        }
    }
}

private struct DayCell: View {
    @Environment(\.uiScale) private var s
    let day: Day
    let selected: Bool
    let today: Bool
    let action: () -> Void

    var body: some View {
        let note = ScheduleDayNote(day)
        Button(action: action) {
            VStack(spacing: 0) {
                Text("\(day.day)")
                    .uiFont(.body, weight: today || selected ? .semibold : .regular, design: .default)
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.white : (today ? Color.accentColor : Color.primary))
                Text(note.label)
                    .uiFont(size: 9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(selected ? AnyShapeStyle(Color.white.opacity(0.9))
                                     : note.special ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            }
            .frame(width: (MonthCalendar.cellHeight - 4) * s, height: (MonthCalendar.cellHeight - 4) * s)
            .background {
                if selected {
                    Circle().fill(Color.accentColor)
                } else if today {
                    Circle().fill(Color.accentColor.opacity(0.12))
                }
            }
            .overlay(alignment: .topTrailing) {
                if let off = note.off {
                    Text(off ? "休" : "班")
                        .uiFont(size: 8, weight: .semibold)
                        .foregroundStyle(off ? Color.red : Color.secondary)
                        .offset(x: 5, y: -1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: MonthCalendar.cellHeight * s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText(note))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func accessibilityText(_ note: ScheduleDayNote) -> String {
        var s = "\(day.month)月\(day.day)日 \(weekdayName(day))"
        if today { s += "，今天" }
        if !note.label.isEmpty { s += "，\(note.special ? "" : "农历")\(note.label)" }
        if let off = note.off { s += off ? "，休" : "，班" }
        return s
    }
}
