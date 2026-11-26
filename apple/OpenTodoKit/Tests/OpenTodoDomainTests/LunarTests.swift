// Ported from app/test/lunar_test.dart, case for case.

import Testing
@testable import OpenTodoDomain

/// Gregorian date → lunar month/day (L for a leap month), from the Chinese
/// calendar of macOS, every 997th day from 1900 and a few picked ones.
private let fromMacOS: [(String, String)] = [
    ("1900-02-01", "1/2"),
    ("1902-10-26", "9/25"),
    ("1905-07-19", "6/17"),
    ("1908-04-11", "3/11"),
    ("1911-01-03", "12/3"),
    ("1913-09-26", "8/26"),
    ("1916-06-19", "5/19"),
    ("1919-03-13", "2/12"),
    ("1921-12-04", "11/6"),
    ("1924-08-27", "7/27"),
    ("1927-05-21", "4/21"),
    ("1930-02-11", "1/13"),
    ("1932-11-04", "10/7"),
    ("1935-07-29", "6/29"),
    ("1938-04-21", "3/21"),
    ("1941-01-12", "12/15"),
    ("1943-10-06", "9/8"),
    ("1946-06-29", "6/1"),
    ("1949-03-22", "2/23"),
    ("1951-12-14", "11/16"),
    ("1954-09-06", "8/10"),
    ("1957-05-30", "5/2"),
    ("1960-02-21", "1/25"),
    ("1962-11-14", "10/18"),
    ("1965-08-07", "7/11"),
    ("1968-04-30", "4/4"),
    ("1971-01-22", "12/26"),
    ("1973-10-15", "9/20"),
    ("1976-07-08", "6/12"),
    ("1979-04-01", "3/5"),
    ("1981-12-23", "11/28"),
    ("1984-09-15", "8/20"),
    ("1987-06-09", "5/14"),
    ("1990-03-02", "2/6"),
    ("1992-11-23", "10/29"),
    ("1995-08-17", "7/22"),
    ("1998-05-10", "4/15"),
    ("2001-01-31", "1/8"),
    ("2003-10-25", "10/1"),
    ("2006-07-18", "6/23"),
    ("2009-04-10", "3/15"),
    ("2012-01-02", "12/9"),
    ("2014-09-25", "9/2"),
    ("2017-06-18", "5/24"),
    ("2020-03-11", "2/18"),
    ("2022-12-03", "11/10"),
    ("2025-08-26", "7/4"),
    ("2028-05-19", "4/25"),
    ("2031-02-10", "1/19"),
    ("2033-11-03", "10/12"),
    ("2036-07-27", "L6/5"),
    ("2039-04-20", "3/27"),
    ("2042-01-11", "12/20"),
    ("2044-10-04", "8/14"),
    ("2047-06-28", "L5/6"),
    ("2050-03-21", "2/29"),
    ("2052-12-12", "10/22"),
    ("2055-09-05", "7/14"),
    ("2058-05-29", "L4/8"),
    ("2061-02-19", "1/30"),
    ("2063-11-13", "9/23"),
    ("2066-08-06", "6/16"),
    ("2069-04-29", "4/9"),
    ("2072-01-21", "12/2"),
    ("2074-10-14", "8/24"),
    ("2077-07-07", "5/18"),
    ("2080-03-30", "3/10"),
    ("2082-12-22", "11/4"),
    ("2085-09-14", "7/26"),
    ("2088-06-07", "L4/18"),
    ("2091-03-01", "1/12"),
    ("2093-11-22", "10/4"),
    ("2096-08-15", "6/27"),
    ("2099-05-09", "3/20"),
    ("2025-07-25", "L6/1"),
    ("2025-08-22", "L6/29"),
    ("2033-12-22", "L11/1"),
    ("2034-01-19", "L11/29"),
    ("2026-02-16", "12/29"),
    ("2100-12-31", "12/1"),
    ("1900-01-31", "1/1"),
]

@Suite("lunar")
struct LunarTests {
    @Test("agrees with the system's Chinese calendar") func agreesWithSystem() throws {
        for (g, l) in fromMacOS {
            let d = try #require(toLunar(Day(g)!), "\(g)")
            #expect("\(d.leap ? "L" : "")\(d.month)/\(d.day)" == l, "\(g)")
            // And back.
            #expect(fromLunar(d.year, d.month, d.day, leap: d.leap)?.key == g)
        }
    }

    @Test("new years and leap months") func newYearsAndLeapMonths() {
        #expect(toLunar(Day(2026, 2, 17)) == LunarDate(2026, 1, 1))
        #expect(toLunar(Day(2026, 2, 16)) == LunarDate(2025, 12, 29)) // 除夕
        // 除夕 in the 2027 notice: 2026's 腊月 has 29 days.
        #expect(toLunar(Day(2027, 2, 5)) == LunarDate(2026, 12, 29))
        #expect(toLunar(Day(2025, 7, 25)) == LunarDate(2025, 6, 1, leap: true))
        #expect(fromLunar(2026, 8, 15) == Day(2026, 9, 25)) // 中秋
        #expect(fromLunar(2027, 8, 15) == Day(2027, 9, 15))
        #expect(lunarMonths(2025).count == 13)
        #expect(lunarMonths(2026).count == 12)
    }

    @Test("days that are not there") func daysThatAreNotThere() {
        #expect(fromLunar(2025, 12, 30) == nil) // 2025's 腊月 has 29 days
        #expect(fromLunar(2025, 12, 30, clampDay: true) == Day(2026, 2, 16))
        #expect(fromLunar(2026, 6, 1, leap: true) == nil)
        #expect(toLunar(Day(1900, 1, 30)) == nil)
        #expect(toLunar(Day(2101, 6, 1)) == nil)
    }

    @Test("names") func names() {
        #expect([1, 10, 11, 15, 20, 21, 29, 30].map(lunarDayName)
            == ["初一", "初十", "十一", "十五", "二十", "廿一", "廿九", "三十"])
        #expect(lunarMonthName(1) == "正月")
        #expect(lunarMonthName(6, leap: true) == "闰六月")
        #expect(lunarMonthName(11) == "冬月")
        #expect(lunarMonthName(12) == "腊月")
        #expect(lunarMonthNumber("腊") == 12)
        #expect(lunarMonthNumber("八") == 8)
        #expect(lunarMonthNumber("十一") == 11)
        #expect(lunarDayNumber("廿三") == 23)
        #expect(lunarDayNumber("初十") == 10)
        #expect(lunarCalendarLabel(toLunar(Day(2026, 11, 9))!) == "十月") // 十月初一
        #expect(lunarCalendarLabel(toLunar(Day(2026, 11, 15))!) == "初七")
    }

    @Test("festivals") func festivals() {
        #expect(lunarFestival(Day(2026, 2, 16)) == "除夕")
        #expect(lunarFestival(Day(2026, 2, 17)) == "春节")
        #expect(lunarFestival(Day(2026, 9, 25)) == "中秋")
        #expect(lunarFestival(Day(2027, 2, 5)) == "除夕")
        #expect(lunarFestival(Day(2026, 11, 15)) == nil)
    }
}
