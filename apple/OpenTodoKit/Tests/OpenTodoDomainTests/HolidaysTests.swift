// Ported from app/test/holidays_test.dart, case for case.

import Testing
@testable import OpenTodoDomain

@Suite("holidays")
struct HolidaysTests {
    @Test("days off and the weekend days worked, by the notices") func daysOffAndWorked() {
        #expect(holidayOn(Day(2026, 2, 15)) == HolidayDay(name: "春节", off: true))
        #expect(holidayOn(Day(2026, 2, 23)) == HolidayDay(name: "春节", off: true))
        #expect(holidayOn(Day(2026, 2, 28)) == HolidayDay(name: "春节", off: false))
        #expect(holidayOn(Day(2026, 9, 20)) == HolidayDay(name: "国庆节", off: false))
        #expect(holidayOn(Day(2025, 10, 6)) == HolidayDay(name: "国庆节、中秋节", off: true))
        #expect(holidayOn(Day(2027, 6, 9)) == HolidayDay(name: "端午节", off: true))
        #expect(holidayOn(Day(2027, 1, 31)) == HolidayDay(name: "春节", off: false))
        #expect(holidayOn(Day(2026, 11, 16)) == nil)
        #expect(Set([2025, 2026, 2027]).isSubset(of: holidayYears))
    }

    @Test("working days") func workingDays() {
        #expect(isWorkday(Day(2026, 11, 16))) // a Monday
        #expect(!isWorkday(Day(2026, 11, 15))) // a Sunday
        #expect(!isWorkday(Day(2026, 10, 1))) // 国庆节, a Thursday
        #expect(isWorkday(Day(2026, 10, 10))) // worked, a Saturday
        // A year without a schedule: just the weekdays.
        #expect(isWorkday(Day(2030, 10, 1)))
        #expect(!isWorkday(Day(2030, 10, 5)))
    }

    @Test("every year adds up: days off are 休 and worked days are weekends") func everyYearAddsUp() {
        for year in holidayYears {
            for d in Day(year, 1, 1)..<Day(year + 1, 1, 1) {
                if let h = holidayOn(d), !h.off {
                    #expect(d.weekday >= 6, "\(d) is worked in exchange")
                }
            }
        }
    }
}
