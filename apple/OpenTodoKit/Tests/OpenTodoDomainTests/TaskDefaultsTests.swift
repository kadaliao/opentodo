// Ported from app/test/task_defaults_test.dart. The Dart round trip went
// through `AppSettings` (the state layer); here it goes through the JSON
// `TaskDefaults` is stored as, which is what `AppSettings` nests.

import Foundation
import Testing
@testable import OpenTodoDomain

private func decode(_ json: String) throws -> TaskDefaults {
    try JSONDecoder().decode(TaskDefaults.self, from: Data(json.utf8))
}

@Suite("task defaults")
struct TaskDefaultsTests {
    @Test("out of the box: 准时 with a time, nothing all day, spans of an hour") func outOfTheBox() {
        let d = TaskDefaults.standard
        #expect(d.remindersFor(allDay: false) == [0])
        #expect(d.remindersFor(allDay: true).isEmpty)
        #expect(d.spanMinutes == 60)
    }

    @Test("round trip, and bad or missing values fall back") func roundTrip() throws {
        let d = TaskDefaults(timedReminders: [-30], allDayReminders: [540, -900], spanMinutes: 90)
        let back = try JSONDecoder().decode(TaskDefaults.self, from: JSONEncoder().encode(d))
        #expect(back == d)
        // The keys the Dart version writes.
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as! [String: Any]
        #expect(Set(json.keys) == ["timedReminders", "allDayReminders", "spanMinutes"])

        let odd = try decode(#"{"timedReminders": "x", "spanMinutes": -5, "allDayReminders": [540, "y"]}"#)
        #expect(odd.timedReminders == [0])
        #expect(odd.allDayReminders == [540])
        #expect(odd.spanMinutes == 60)
        #expect(try decode("{}") == TaskDefaults.standard)
        #expect(try decode(#"{"spanMinutes": 45.0, "timedReminders": [-5.0]}"#)
            == TaskDefaults(timedReminders: [-5], spanMinutes: 45))
    }
}
