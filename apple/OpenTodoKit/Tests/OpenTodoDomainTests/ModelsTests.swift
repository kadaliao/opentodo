import Foundation
import Testing
@testable import OpenTodoDomain

@Suite("models")
struct ModelsTests {
    @Test func defaultsMatchTheDatabaseDefaults() {
        let t = TodoTask(id: "a")
        #expect(t.listId == inboxListId)
        #expect(t.content == "" && t.priority == .none && t.status == .open)
        #expect(t.tags == [] && t.reminders == [] && t.repeatFrom == .dueDate)
        #expect(t.sortOrder == 0 && t.serverVersion == 0 && t.dirty)
        #expect(TaskFilter(id: "f").rule == "{}")
        #expect(!ChecklistItem(id: "c").done)
    }

    @Test func rawValuesMatchDart() {
        #expect(TaskStatus.allCases.map(\.rawValue) == [0, 1, 2])
        #expect(Priority.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(RepeatFrom.allCases.map(\.rawValue) == [0, 1])
        #expect(Priority.high > Priority.low)
        #expect(Priority(clamping: 9) == .high)
        #expect(Priority(clamping: -1) == .none)
    }

    @Test func codableRoundTrip() throws {
        let t = TodoTask(
            id: "a", listId: "l", sectionId: "s", title: "买菜", priority: .high,
            dueDate: Day(2026, 11, 15), dueTime: 540, duration: 60, tags: ["家"],
            status: .done, reminders: [0, -30], repeatRule: "FREQ=DAILY", repeatFrom: .completion,
            createdAt: 1, updatedAt: 2
        )
        let data = try JSONEncoder().encode(t)
        #expect(try JSONDecoder().decode(TodoTask.self, from: data) == t)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["dueDate"] as? String == "2026-11-15")
        #expect(json["priority"] as? Int == 3)
    }

    @Test func unknownNumbersFallBack() throws {
        struct Box: Decodable { var s: TaskStatus; var p: Priority; var r: RepeatFrom }
        let b = try JSONDecoder().decode(Box.self, from: Data(#"{"s": 7, "p": 5, "r": 9}"#.utf8))
        #expect(b.s == .open && b.p == .high && b.r == .dueDate)
    }
}
