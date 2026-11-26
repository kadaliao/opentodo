// What a task gets when the person doesn't say: its reminders when it is
// given a date or a time, and how long a new span lasts. Set in 设置.
// Ported from `app/lib/domain/task_defaults.dart`.
//
// `Codable` as the Dart `toJson` / `fromJson` JSON (it sits under
// `defaults` in the settings JSON in `key_values`): `timedReminders`,
// `allDayReminders`, `spanMinutes`. Decoding never fails: a missing or
// unusable value takes the standard one, and non-numbers in a list are
// dropped.

public struct TaskDefaults: Sendable, Hashable {
    /// For a task with a time: 准时 unless the person chose otherwise.
    public var timedReminders: [Int]

    /// For an all-day task: none unless the person chose, say, 当天 09:00.
    public var allDayReminders: [Int]

    /// How long a span is when the person first asks for one.
    public var spanMinutes: Int

    public init(timedReminders: [Int] = [0], allDayReminders: [Int] = [], spanMinutes: Int = defaultSpanMinutes) {
        self.timedReminders = timedReminders
        self.allDayReminders = allDayReminders
        self.spanMinutes = spanMinutes
    }

    public static let standard = TaskDefaults()

    public func remindersFor(allDay: Bool) -> [Int] { allDay ? allDayReminders : timedReminders }
}

extension TaskDefaults: Codable {
    private enum CodingKeys: String, CodingKey {
        case timedReminders, allDayReminders, spanMinutes
    }

    public init(from decoder: any Decoder) throws {
        let standard = TaskDefaults.standard
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = standard
            return
        }
        func ints(_ key: CodingKeys) -> [Int]? {
            (try? c.decode([LossyNumber].self, forKey: key))?.compactMap(\.value)
        }
        let span = (try? c.decode(LossyNumber.self, forKey: .spanMinutes))?.number
        self.init(
            timedReminders: ints(.timedReminders) ?? standard.timedReminders,
            allDayReminders: ints(.allDayReminders) ?? standard.allDayReminders,
            spanMinutes: span.flatMap { $0 > 0 ? Int($0) : nil } ?? standard.spanMinutes
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(timedReminders, forKey: .timedReminders)
        try c.encode(allDayReminders, forKey: .allDayReminders)
        try c.encode(spanMinutes, forKey: .spanMinutes)
    }
}

/// A JSON value that is a number (kept, as Dart's `num.toInt()` would) or
/// anything else (`value` nil). Never fails to decode.
private struct LossyNumber: Decodable {
    let number: Double?

    var value: Int? { number.map { Int($0) } }

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            number = Double(i)
        } else if let d = try? c.decode(Double.self), d.isFinite, abs(d) < 1e15 {
            number = d
        } else {
            number = nil
        }
    }
}
