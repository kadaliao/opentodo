// iOS QA: a phone held upright doesn't offer the week and multi-week views
// (seven columns too narrow to read a task in, as the system Calendar);
// a stored week or multi-week shows as 3 days or the month there, and the
// wide window keeps the choice.

import OpenTodoDomain
import Testing
@testable import OpenTodoUI

@Suite @MainActor
struct CalendarCompactTests {
    @Test func aNarrowScreenOffersNoWeekOrMultiWeek() {
        #expect(CalendarLogic.modesOffered(compact: false) == CalendarLogic.modesOffered)
        #expect(CalendarLogic.modesOffered(compact: true) == [.day, .threeDays, .month, .year, .agenda])
        #expect(CalendarLogic.shownMode(.week, compact: true) == .threeDays)
        #expect(CalendarLogic.shownMode(.multiWeek, compact: true) == .month)
        for m in [CalendarMode.day, .threeDays, .month, .year, .agenda] {
            #expect(CalendarLogic.shownMode(m, compact: true) == m)
        }
        for m in CalendarMode.allCases { #expect(CalendarLogic.shownMode(m, compact: false) == m) }
    }

    @Test func aStoredWeekShowsAsThreeDaysOnAPhoneAndStaysForTheWideWindow() {
        let today = Day(2026, 11, 26) // a Thursday
        var saved: [CalendarPrefs] = []
        let m = CalendarModel(anchor: today)
        m.savePrefs = { saved.append($0) }
        m.perform(.mode(.week), today: today) // a keyboard shortcut, or the prefs as stored
        #expect(m.mode == .week)
        #expect(m.range.length == 7)
        m.compact = true
        #expect(m.mode == .threeDays)
        #expect(m.range.length == 3)
        // Paging moves by the 3 days shown.
        m.perform(.page(1), today: today)
        #expect(m.anchor == today + 3)
        #expect(m.prefs.mode == .week) // not overwritten
        m.compact = false
        #expect(m.mode == .week)
        m.compact = true
        m.mode = .multiWeek
        #expect(m.mode == .month)
        #expect(saved.last?.mode == .multiWeek)
    }
}
