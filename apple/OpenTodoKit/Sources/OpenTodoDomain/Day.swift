// Wall-clock date and time, without a time zone.
//
// Task dates float: a task due on the 18th stays on the 18th when the device
// travels, and 提前1天 stays at the same clock time across a DST change. So
// the domain never does arithmetic on `Date` (an instant); it uses
//
// - `Day`: a calendar date (proleptic Gregorian), stored as a Julian day
//   number. It is what the database's `YYYY-MM-DD` columns hold.
// - `LocalDateTime`: a `Day` plus minutes after midnight (0..<1440). It is
//   the Dart version's local `DateTime` when that stands for "a wall-clock
//   moment" (`now`, a reminder's time, the end of a span). Minute precision:
//   seconds are dropped when one is made from a `Date`.
//
// All arithmetic is plain integers, so results never depend on the
// machine's time zone. Only the conversions to and from `Date` take a
// `TimeZone` (default `.current`); the UI and data layers do those at the
// edges and pass `Day`s and `LocalDateTime`s into the pure domain functions,
// like the Dart version passes `today` / `now`.
//
//     let d = Day(2026, 11, 15)            // like Dart DateTime(2026, 11, 15)
//     Day("2026-11-15")                    // parse, nil if invalid (parseDateKey);
//                                          // tests write Day("2026-11-15")!
//     d.key                                // "2026-11-15" (dateKey)
//     d.year, d.month, d.day, d.weekday    // weekday: Monday 1 … Sunday 7, as in Dart
//     d + 3, d - 1, d.adding(days: 3)      // addDays
//     b - a, a.days(to: b)                 // daysBetween(a, b)
//     for x in a..<b { … }                 // Strideable, by day
//     d.startOfWeek                        // that week's Monday
//     d.startOfMonth, d.endOfMonth, d.daysInMonth, Day.daysIn(year:month:)
//     d.addingMonths(1)                    // same day next month, clamped (Jan 31 → Feb 28)
//     Day(2026, 13, 0)                     // out-of-range parts roll over like Dart's
//                                          // DateTime: here 2026-12-31
//     Day.valid(2026, 2, 30)               // nil: strict, for parsing user input
//     Day.today(in: tz, now: date)         // from a `Date`; also Day(date, in: tz)
//     d.start(in: tz)                      // the `Date` its midnight falls on
//
//     let t = LocalDateTime(d, minute: 22 * 60)   // like DateTime(y, m, d, 0, minutes):
//     LocalDateTime(2026, 11, 15, 22, 30)         // overflow rolls into other days
//     t.day, t.minuteOfDay, t.hour, t.minute
//     t + 90, t - 30, t.adding(minutes: 90), b - a   // minutes
//     LocalDateTime.now(in: tz), LocalDateTime(date, in: tz), t.date(in: tz)
//
// Both are `Codable` as their text form (`"2026-11-15"`, `"2026-11-15T22:30"`),
// so they can go straight into the JSON kept in `key_values`.

import Foundation

// MARK: - Day

public struct Day: Sendable, Hashable, Comparable, Strideable {
    /// Days since the Julian epoch (noon, 1 January 4713 BC, proleptic Julian).
    /// Day 0 was a Monday, which is what `weekday` relies on.
    public let julianDay: Int

    public init(julianDay: Int) {
        self.julianDay = julianDay
    }

    /// A date from its parts. Like Dart's `DateTime(year, month, day)`, parts
    /// out of range roll over: month 13 is January of the next year, day 0 is
    /// the last day of the month before. Use `valid(_:_:_:)` to reject them.
    public init(_ year: Int, _ month: Int, _ day: Int) {
        let m0 = month - 1
        let y = year + floorDiv(m0, 12)
        let m = floorMod(m0, 12) + 1
        julianDay = Day.julianDay(y, m, 1) + day - 1
    }

    /// The date, or nil if the parts don't name one (2月30日, month 13).
    public static func valid(_ year: Int, _ month: Int, _ day: Int) -> Day? {
        guard (1...12).contains(month), day >= 1, day <= daysIn(year: year, month: month) else { return nil }
        return Day(year, month, day)
    }

    /// Parses `YYYY-MM-DD` (each part may have fewer digits, not more). Nil unless it
    /// names a real date.
    public init?(_ key: some StringProtocol) {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              zip(parts, [4, 2, 2]).allSatisfy({ part, width in
                  !part.isEmpty && part.count <= width && part.allSatisfy(\.isASCIIDigit)
              }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              let day = Day.valid(y, m, d)
        else { return nil }
        self = day
    }

    // MARK: Parts

    public var year: Int { parts.year }
    public var month: Int { parts.month }
    public var day: Int { parts.day }

    /// Year, month and day at once (cheaper than asking for each).
    public var parts: (year: Int, month: Int, day: Int) {
        // Richards' algorithm, Gregorian.
        let a = julianDay + 32044
        let b = (4 * a + 3) / 146_097
        let c = a - 146_097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        return (100 * b + d - 4800 + m / 10, m + 3 - 12 * (m / 10), e - (153 * m + 2) / 5 + 1)
    }

    /// Monday 1 … Sunday 7, the same numbers as Dart's `DateTime.weekday`.
    public var weekday: Int { floorMod(julianDay, 7) + 1 }

    /// `YYYY-MM-DD`, the form the database and the sync protocol use.
    public var key: String {
        let (y, m, d) = parts
        return pad(y, 4) + "-" + pad(m, 2) + "-" + pad(d, 2)
    }

    // MARK: Arithmetic

    public func adding(days: Int) -> Day { Day(julianDay: julianDay + days) }

    /// Whole calendar days from `self` to `other` (negative if `other` is
    /// earlier). Dart's `daysBetween(self, other)`.
    public func days(to other: Day) -> Int { other.julianDay - julianDay }

    /// The same day `months` months on, clamped to the end of a shorter
    /// month: 1月31日 + 1 → 2月28日. (Dart code that writes
    /// `DateTime(y, m + n, d)` rolls over instead; port that as
    /// `Day(year, month + n, day)`.)
    public func addingMonths(_ months: Int) -> Day {
        let (y, m, d) = parts
        let first = Day(y, m + months, 1)
        return Day(first.year, first.month, min(d, first.daysInMonth))
    }

    public static func + (lhs: Day, rhs: Int) -> Day { lhs.adding(days: rhs) }
    public static func - (lhs: Day, rhs: Int) -> Day { lhs.adding(days: -rhs) }
    /// Days from `rhs` to `lhs`.
    public static func - (lhs: Day, rhs: Day) -> Int { rhs.days(to: lhs) }
    public static func += (lhs: inout Day, rhs: Int) { lhs = lhs + rhs }
    public static func -= (lhs: inout Day, rhs: Int) { lhs = lhs - rhs }

    public func advanced(by n: Int) -> Day { adding(days: n) }
    public func distance(to other: Day) -> Int { days(to: other) }
    public static func < (lhs: Day, rhs: Day) -> Bool { lhs.julianDay < rhs.julianDay }

    // MARK: Weeks and months

    /// Monday of the week this day is in.
    public var startOfWeek: Day { adding(days: 1 - weekday) }
    public var startOfMonth: Day { Day(julianDay: julianDay - day + 1) }
    public var endOfMonth: Day { let (y, m, _) = parts; return Day(y, m, Day.daysIn(year: y, month: m)) }
    public var daysInMonth: Int { let (y, m, _) = parts; return Day.daysIn(year: y, month: m) }

    public static func isLeapYear(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    /// Days in `month` (1–12) of `year`.
    public static func daysIn(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    // MARK: Foundation

    /// The calendar date `date` falls on in `timeZone`.
    public init(_ date: Date, in timeZone: TimeZone = .current) {
        let c = gregorian(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(c.year!, c.month!, c.day!)
    }

    /// Today in `timeZone`; pass `now` to pin the clock.
    public static func today(in timeZone: TimeZone = .current, now: Date = .now) -> Day {
        Day(now, in: timeZone)
    }

    /// The first moment of this day in `timeZone` (its midnight, or the
    /// first minute after it where DST skips midnight).
    public func start(in timeZone: TimeZone = .current) -> Date {
        gregorian(timeZone).startOfDay(for: LocalDateTime(self, minute: 12 * 60).date(in: timeZone))
    }

    // MARK: Private

    private static func julianDay(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let a = (14 - m) / 12
        let y2 = y + 4800 - a
        let m2 = m + 12 * a - 3
        return d + (153 * m2 + 2) / 5 + 365 * y2 + floorDiv(y2, 4) - floorDiv(y2, 100) + floorDiv(y2, 400) - 32045
    }
}

extension Day: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { key }
    public var debugDescription: String { key }
}

extension Day: Codable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let day = Day(s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a YYYY-MM-DD date: \(s)")
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(key)
    }
}

// MARK: - LocalDateTime

/// A wall-clock moment: a `Day` and minutes after its midnight. See the top
/// of this file.
public struct LocalDateTime: Sendable, Hashable, Comparable {
    public let day: Day
    /// 0..<1440.
    public let minuteOfDay: Int

    /// `minute` minutes after the midnight that starts `day`; outside
    /// 0..<1440 it rolls into other days, like Dart's
    /// `DateTime(y, m, d, 0, minute)`.
    public init(_ day: Day, minute: Int = 0) {
        self.day = day.adding(days: floorDiv(minute, minutesPerDay))
        minuteOfDay = floorMod(minute, minutesPerDay)
    }

    /// Like Dart's `DateTime(year, month, day, hour, minute)`: every part
    /// rolls over.
    public init(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) {
        self.init(Day(year, month, day), minute: hour * 60 + minute)
    }

    public var hour: Int { minuteOfDay / 60 }
    /// Minute of the hour, 0–59 (Dart's `DateTime.minute`).
    public var minute: Int { minuteOfDay % 60 }

    /// Minutes since the Julian epoch; what comparisons and differences use.
    public var totalMinutes: Int { day.julianDay * minutesPerDay + minuteOfDay }

    public func adding(minutes: Int) -> LocalDateTime { LocalDateTime(day, minute: minuteOfDay + minutes) }

    public static func + (lhs: LocalDateTime, rhs: Int) -> LocalDateTime { lhs.adding(minutes: rhs) }
    public static func - (lhs: LocalDateTime, rhs: Int) -> LocalDateTime { lhs.adding(minutes: -rhs) }
    /// Minutes from `rhs` to `lhs`.
    public static func - (lhs: LocalDateTime, rhs: LocalDateTime) -> Int { lhs.totalMinutes - rhs.totalMinutes }
    public static func < (lhs: LocalDateTime, rhs: LocalDateTime) -> Bool { lhs.totalMinutes < rhs.totalMinutes }

    /// `YYYY-MM-DDTHH:MM`.
    public var key: String { day.key + "T" + pad(hour, 2) + ":" + pad(minute, 2) }

    /// Parses `YYYY-MM-DDTHH:MM`.
    public init?(_ key: some StringProtocol) {
        let halves = key.split(separator: "T", omittingEmptySubsequences: false)
        guard halves.count == 2, let day = Day(halves[0]) else { return nil }
        let hm = halves[1].split(separator: ":", omittingEmptySubsequences: false)
        guard hm.count == 2, hm.allSatisfy({ (1...2).contains($0.count) && $0.allSatisfy(\.isASCIIDigit) }),
              let h = Int(hm[0]), let m = Int(hm[1]), h < 24, m < 60
        else { return nil }
        self.init(day, minute: h * 60 + m)
    }

    // MARK: Foundation

    /// The wall-clock time `date` shows in `timeZone`, seconds dropped.
    public init(_ date: Date, in timeZone: TimeZone = .current) {
        let c = gregorian(timeZone).dateComponents([.year, .month, .day, .hour, .minute], from: date)
        self.init(c.year!, c.month!, c.day!, c.hour!, c.minute!)
    }

    /// Now in `timeZone`, to the minute; pass `now` to pin the clock.
    public static func now(in timeZone: TimeZone = .current, now: Date = .now) -> LocalDateTime {
        LocalDateTime(now, in: timeZone)
    }

    /// The instant this wall-clock time names in `timeZone`. A time DST
    /// skips (02:30 on the night clocks go forward) moves on to the next
    /// valid time; a time that happens twice gives the first.
    public func date(in timeZone: TimeZone = .current) -> Date {
        let (y, m, d) = day.parts
        let c = DateComponents(year: y, month: m, day: d, hour: hour, minute: minute)
        return gregorian(timeZone).date(from: c)!
    }
}

extension LocalDateTime: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { key }
    public var debugDescription: String { key }
}

extension LocalDateTime: Codable {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let t = LocalDateTime(s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a YYYY-MM-DDTHH:MM time: \(s)")
        }
        self = t
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(key)
    }
}

// MARK: - Helpers

/// Integer division rounding towards negative infinity.
@inlinable func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}

/// The remainder that is never negative for a positive `b`, like Dart's `%`.
@inlinable func floorMod(_ a: Int, _ b: Int) -> Int {
    let r = a % b
    return r < 0 ? r + b : r
}

private func pad(_ n: Int, _ width: Int) -> String {
    let s = String(n)
    return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
}

private func gregorian(_ timeZone: TimeZone) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = timeZone
    return c
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
