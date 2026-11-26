// Port of app/test/sync_codec_test.dart. Where the Dart test makes rows
// with TaskRepo, these build the models directly (what addTask would
// store at 2026-11-15 10:00).

import Foundation
import Testing
@testable import OpenTodoData

/// Through JSON text, as on the wire, with a version from the server.
func trip(_ r: WireRecord, version: Int) throws -> WireRecord {
    guard var pairs = JSONValue(parsing: r.json.encoded())?.pairs else { throw JSONParseError() }
    pairs.append(("version", .int(version)))
    return try #require(WireRecord(json: try JSONValue.decode(JSONValue.fields(pairs).encoded())))
}

@Suite struct SyncCodecTests {
    let now = nowMilliseconds(LocalDateTime(2026, 11, 15, 10).date())

    @Test("a task survives the trip to the server and back")
    func taskTrip() async throws {
        let a = try AppDatabase.inMemory()
        let b = try AppDatabase.inMemory()
        let original = TodoTask(
            id: Ids.newId(), title: "开会", content: "带上电脑", priority: .high,
            dueDate: Day(2026, 11, 16), dueTime: 900, duration: 90, tags: ["工作", "重要"],
            reminders: [0, -30], repeatRule: "FREQ=WEEKLY;BYDAY=MO", repeatFrom: .completion,
            sortOrder: -Double(now), createdAt: now, updatedAt: now + 1
        )
        try await a.writer.write { try original.insert($0) }
        let stored = try #require(try await a.observeTasks().first().first)
        #expect(stored == original)

        let wire = try trip(stored.wire, version: 7)
        try await b.writer.write { try TodoTask(wire: wire).insert($0) }
        let copy = try #require(try await b.observeTasks().first().first { $0.id == original.id })

        var same = copy
        same.dirty = true
        same.serverVersion = 0
        #expect(same == original)
        #expect(!copy.dirty)
        #expect(copy.serverVersion == 7)
    }

    @Test("missing fields fall back to defaults; unknown ones are ignored")
    func defaults() throws {
        let wire = try #require(WireRecord(json: try JSONValue.decode("""
            {"entity":"task","id":"x","updatedAt":5,"deletedAt":null,
             "data":{"title":"旧客户端写的","someFutureField":1},"version":1}
            """)))
        let c = TodoTask(wire: wire)
        #expect(c.title == "旧客户端写的")
        #expect(c.listId == inboxListId)
        #expect(c.tags.isEmpty)
        #expect(c.createdAt == 5)
        #expect(c.reminders.isEmpty)
        #expect(c.repeatRule == nil)
        #expect(c.repeatFrom == .dueDate)
        #expect(c.duration == nil)
    }

    @Test("a filter travels with its rule as an object")
    func filterTrip() async throws {
        let a = try AppDatabase.inMemory()
        let b = try AppDatabase.inMemory()
        let rule = #"{"match":"all","conditions":[{"field":"priority","values":["high"]}]}"#
        let original = TaskFilter(id: Ids.newId(), name: "重要", rule: rule, sortOrder: Double(now), createdAt: now, updatedAt: now)
        try await a.writer.write { try original.insert($0) }
        let stored = try #require(try await a.observeFilters().first().first)

        let wire = stored.wire
        #expect(wire["rule"]?.isObject == true)
        let back = try trip(wire, version: 3)
        try await b.writer.write { try TaskFilter(wire: back).insert($0) }
        let copy = try #require(try await b.observeFilters().first().first)
        var same = copy
        same.dirty = true
        same.serverVersion = 0
        #expect(same == original)
        #expect(copy.rule == rule)

        // A record without a rule, or with a broken one, reads as "everything".
        let bare = TaskFilter(wire: try #require(WireRecord(json: try JSONValue.decode("""
            {"entity":"filter","id":"y","updatedAt":5,"deletedAt":null,"data":{"name":"旧的","rule":"oops"}}
            """))))
        #expect(bare.rule == "{}")
        // And one whose rule text isn't an object goes out as {}.
        #expect(TaskFilter(id: "z", rule: "oops").wire["rule"] == .fields([]))
    }

    @Test("a section travels, and a task keeps its section")
    func sectionTrip() async throws {
        let a = try AppDatabase.inMemory()
        let b = try AppDatabase.inMemory()
        let section = ListSection(id: Ids.newId(), listId: "work", name: "进行中", sortOrder: 0, createdAt: now, updatedAt: now)
        let task = TodoTask(id: Ids.newId(), listId: "work", sectionId: section.id, title: "写周报", sortOrder: -Double(now), createdAt: now, updatedAt: now)
        try await a.writer.write { db in
            try section.insert(db)
            try task.insert(db)
        }
        let storedSection = try #require(try await a.observeSections().first().first)
        let storedTask = try #require(try await a.observeTasks().first().first)

        try await b.writer.write { db in
            try ListSection(wire: try trip(storedSection.wire, version: 2)).insert(db)
            try TodoTask(wire: try trip(storedTask.wire, version: 2)).insert(db)
        }
        let copy = try #require(try await b.observeSections().first().first)
        var same = copy
        same.dirty = true
        same.serverVersion = 0
        #expect(same == section)
        #expect(try await b.observeTasks().first().first?.sectionId == section.id)

        // From a version without sections: none.
        let old = TodoTask(wire: try #require(WireRecord(json: try JSONValue.decode("""
            {"entity":"task","id":"z","updatedAt":5,"deletedAt":null,"data":{"title":"旧的"}}
            """))))
        #expect(old.sectionId == nil)
    }

    // MARK: Swift version only

    @Test("the wire format, field by field and in order")
    func wireText() {
        let t = TodoTask(id: "t", listId: "work", title: "a\"b", dueDate: Day(2026, 11, 16), tags: ["家"], reminders: [0, -30],
                         sortOrder: 512, createdAt: 1, updatedAt: 2)
        #expect(t.wire.json.encoded() == #"{"entity":"task","id":"t","updatedAt":2,"deletedAt":null,"data":{"listId":"work","sectionId":null,"title":"a\"b","content":"","priority":0,"dueDate":"2026-11-16","dueTime":null,"duration":null,"timeZone":null,"tags":["家"],"status":0,"completedAt":null,"reminders":[0,-30],"repeatRule":null,"repeatFrom":0,"pinnedAt":null,"trashedAt":null,"sortOrder":512.0,"createdAt":1}}"#)
        let l = TaskList(id: "l", name: "工作", emoji: "💼", color: 0xFF14A38B, sortOrder: 1.5, createdAt: 1, updatedAt: 2, deletedAt: 3)
        #expect(l.wire.json.encoded() == #"{"entity":"list","id":"l","updatedAt":2,"deletedAt":3,"data":{"name":"工作","emoji":"💼","color":4279542667,"sortOrder":1.5,"createdAt":1}}"#)
        let c = ChecklistItem(id: "c", taskId: "t", title: "x", done: true, createdAt: 1, updatedAt: 2)
        #expect(c.wire.json.encoded() == #"{"entity":"checklist","id":"c","updatedAt":2,"deletedAt":null,"data":{"taskId":"t","title":"x","done":true,"sortOrder":0.0,"createdAt":1}}"#)
        let s = ListSection(id: "s", listId: "l", name: "n", createdAt: 1, updatedAt: 2)
        #expect(s.wire.json.encoded() == #"{"entity":"section","id":"s","updatedAt":2,"deletedAt":null,"data":{"listId":"l","name":"n","sortOrder":0.0,"createdAt":1}}"#)
    }

    @Test("readers take what they can: numbers of either kind, wrong types as defaults")
    func lenientReads() throws {
        let w = try #require(WireRecord(json: try JSONValue.decode("""
            {"entity":"task","id":"x","updatedAt":5.0,"deletedAt":7,"data":{
              "title":3,"priority":2.0,"dueDate":"2026-02-30","dueTime":540,"tags":["a",1,"b"],
              "reminders":[0,-10.0,"x"],"status":9,"repeatFrom":1,"sortOrder":3,"createdAt":4}}
            """)))
        let t = TodoTask(wire: w)
        #expect(t.title == "")
        #expect(t.priority == .medium)
        #expect(t.dueDate == nil)
        #expect(t.dueTime == 540)
        #expect(t.tags == ["a", "b"])
        #expect(t.reminders == [0, -10])
        #expect(t.status == .open)
        #expect(t.repeatFrom == .completion)
        #expect(t.sortOrder == 3)
        #expect(t.createdAt == 4)
        #expect(t.updatedAt == 5)
        #expect(t.deletedAt == 7)
        #expect(t.serverVersion == 0)
        #expect(!t.dirty)

        #expect(WireRecord(json: try JSONValue.decode(#"{"entity":"task","id":"x"}"#)) == nil)
        let noData = try #require(WireRecord(json: try JSONValue.decode(#"{"entity":"list","id":"x","updatedAt":1}"#)))
        #expect(TaskList(wire: noData).name == "")
        #expect(ChecklistItem(wire: noData).done == false)
    }
}

@Suite struct IdsTests {
    @Test("occurrence ids are the standard UUID v5, as package:uuid makes them")
    func v5() {
        #expect(uuidV5(namespace: "6ba7b810-9dad-11d1-80b4-00c04fd430c8", name: "python.org") == "886313e1-3b8a-5372-9b90-0c9aee199e5d")
        #expect(Ids.occurrenceId(of: "task-1", dueDate: Day(2026, 11, 15)) == "a164f766-269d-53af-b25d-b1da3c76ad45")
    }

    /// Printed by package:uuid 4.6.0 (the Flutter version's) for
    /// `Uuid().v5(_occurrenceNamespace, '$id/${t.dueDate}')`.
    @Test("occurrence ids match the Flutter version's, byte for byte",
          arguments: [
              ("task-1", Day(2026, 11, 26), "61c62a68-1d51-54a1-9840-34247406fb10"),
              ("0193a1b2-0000-7000-8000-000000000000", Day(2026, 1, 1), "4b3b7488-2d3a-5e10-8859-fc354665d450"),
              ("中文id", Day(2026, 12, 31), "2be3570a-159e-50a8-849e-5d4875260c08"),
              ("seed-today", Day(2026, 2, 28), "ff03f79a-4b8b-52a9-a6c9-f29f2b3a3d0e"),
          ])
    func v5MatchesDart(id: String, due: Day, expected: String) {
        #expect(Ids.occurrenceId(of: id, dueDate: due) == expected)
    }

    @Test("new ids are UUID v7, ordered by time")
    func v7() {
        let a = Ids.newId(now: Date(timeIntervalSince1970: 1_000))
        let b = Ids.newId(now: Date(timeIntervalSince1970: 2_000))
        #expect(a.count == 36)
        #expect(Array(a)[14] == "7")
        #expect("89ab".contains(Array(a)[19]))
        #expect(a < b)
        #expect(a == a.lowercased())
        #expect(UUID(uuidString: a) != nil)
    }
}

/// The domain's `JSONValue`, as the data layer relies on it.
@Suite struct JSONTests {
    @Test("keys keep their order, both ways")
    func order() throws {
        let text = #"{"z":1,"a":[true,false,null],"m":{"b":"x","a":-0.5}}"#
        #expect(try JSONValue.decode(text).encoded() == text)
        #expect(JSONValue.fields([("b", .int(1)), ("a", .int(2))]).encoded() == #"{"b":1,"a":2}"#)
        #expect(try JSONValue.decode(text).pairs?.map(\.0) == ["z", "a", "m"])
    }

    @Test("writes what Dart's jsonEncode writes")
    func dartStyle() {
        let v: JSONValue = .array([.string("a/b \"q\" \\ \n\t\u{01} 中文 😀"), .int(-3), .double(512), .double(0.25), .double(1e21)])
        #expect(v.encoded() == #"["a/b \"q\" \\ \n\t\u0001 中文 😀",-3,512.0,0.25,1e+21]"#)
    }

    @Test("reads escapes, surrogate pairs and number kinds")
    func parsing() throws {
        #expect(try JSONValue.decode(#""中😀\/""#) == .string("中😀/"))
        #expect(try JSONValue.decode("12") == .int(12))
        #expect(try JSONValue.decode("12.0") == .double(12))
        #expect(try JSONValue.decode("1e3") == .double(1000))
        #expect(try JSONValue.decode(" [ ] ") == .array([]))
        #expect(try JSONValue.decode("{}") == .fields([]))
        for bad in ["", "[1,]", "{\"a\"}", "01", "tru", "\"abc", "1 2", "{'a':1}"] {
            #expect(JSONValue.parse(bad) == nil, "\(bad)")
        }
    }

    @Test("Bool and numbers stay apart; reads are lenient")
    func kinds() throws {
        let v = try JSONValue.decode("[1,true,0,2.9,\"x\"]")
        #expect(v.arrayValue?.map(\.boolValue) == [nil, true, nil, nil, nil])
        #expect(v.arrayValue?.map(\.intValue) == [1, nil, 0, 2, nil])
        #expect(v.arrayValue?.map(\.stringValue) == [nil, nil, nil, nil, "x"])
    }
}
