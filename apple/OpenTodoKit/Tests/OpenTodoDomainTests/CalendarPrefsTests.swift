// `CalendarPrefs` (app/lib/state/calendar_providers.dart): the Flutter
// version has no unit test of its own for it; these pin the JSON it writes
// and reads.

import Foundation
import Testing
@testable import OpenTodoDomain

private func decode(_ json: String) throws -> CalendarPrefs {
    try JSONDecoder().decode(CalendarPrefs.self, from: Data(json.utf8))
}

@Suite("calendar prefs")
struct CalendarPrefsTests {
    @Test("out of the box: the month, everything shown") func defaults() {
        let p = CalendarPrefs.standard
        #expect(p.mode == .month)
        #expect(p.showCompleted && p.showRepeats && p.showLunar)
        #expect(p.hiddenLists.isEmpty)
        #expect(p.filter == CalendarFilter())
        #expect(CalendarPrefs.storageKey == "calendar.prefs")
    }

    @Test("reads what the Flutter version writes") func readsFlutter() throws {
        // jsonEncode(CalendarPrefs(mode: week, showLunar: false, hiddenLists: {inbox, work}).toJson())
        let p = try decode(#"{"mode":"week","showCompleted":true,"showRepeats":false,"showLunar":false,"hiddenLists":["inbox","work"]}"#)
        #expect(p == CalendarPrefs(mode: .week, showRepeats: false, showLunar: false, hiddenLists: [inboxListId, "work"]))
        #expect(p.filter == CalendarFilter(showRepeats: false, hiddenLists: ["inbox", "work"]))
    }

    @Test("writes the same keys and values, and reads them back") func roundTrip() throws {
        let p = CalendarPrefs(mode: .threeDays, showCompleted: false, hiddenLists: ["b", "a"])
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(CalendarPrefs.self, from: data) == p)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["mode", "showCompleted", "showRepeats", "showLunar", "hiddenLists", "weeks", "taskCard"])
        #expect(json["mode"] as? String == "threeDays")
        #expect(json["showCompleted"] as? Bool == false)
        #expect(json["hiddenLists"] as? [String] == ["a", "b"])
    }

    @Test("unknown or missing values fall back to the defaults") func fallbacks() throws {
        #expect(try decode("{}") == .standard)
        let odd = try decode(#"{"mode":"decade","showCompleted":"no","showLunar":0,"hiddenLists":["work",3,null]}"#)
        #expect(odd == CalendarPrefs(hiddenLists: ["work"]))
        #expect(try decode(#"{"hiddenLists":"work"}"#).hiddenLists.isEmpty)
        // Not an object at all.
        #expect(try decode("[1]") == .standard)
    }

    @Test("the filter and the card choice are kept; the Flutter version's JSON has neither") func filterAndCard() throws {
        let p = CalendarPrefs(filterId: "important-week", taskCard: true)
        let back = try JSONDecoder().decode(CalendarPrefs.self, from: JSONEncoder().encode(p))
        #expect(back.filterId == "important-week" && back.taskCard)
        let flutter = try decode(#"{"mode":"week","showCompleted":true,"showRepeats":true,"showLunar":true,"hiddenLists":[]}"#)
        #expect(flutter.filterId == nil && !flutter.taskCard)
        #expect(try decode(#"{"filterId":"","taskCard":"yes"}"#).filterId == nil)
    }
}
