// Tasks dropped on a sidebar row (macOS): what each row does with them,
// and that only the drag this window started counts.

import OpenTodoDomain
import Testing
@testable import OpenTodoUI

private let sdToday = Day(2026, 11, 28)
private let sdA = TodoTask(id: "a", listId: "work", title: "a", dueDate: sdToday, dueTime: 600, tags: ["x"])
private let sdB = TodoTask(id: "b", listId: inboxListId, title: "b")
private let sdDone = TodoTask(id: "d", listId: "work", title: "d", status: .done)

@Suite("Sidebar drop")
@MainActor
struct SidebarDropTests {
    @Test("今天 / 明天: that day, each keeping its time; those already there stay")
    func days() {
        #expect(sidebarDropAction(.smart(.today), [sdA, sdB], today: sdToday)
            == .setDue([BatchDueChange(id: "b", date: sdToday, time: nil)]))
        #expect(sidebarDropAction(.smart(.tomorrow), [sdA, sdB], today: sdToday)
            == .setDue([BatchDueChange(id: "a", date: sdToday + 1, time: 600), BatchDueChange(id: "b", date: sdToday + 1, time: nil)]))
        #expect(sidebarDropAction(.smart(.today), [sdA], today: sdToday) == nil)
    }

    @Test("a list or 收集箱: moved there")
    func lists() {
        #expect(sidebarDropAction(.list("life"), [sdA, sdB], today: sdToday) == .moveToList(ids: ["a", "b"], listId: "life"))
        #expect(sidebarDropAction(.smart(.inbox), [sdA, sdB], today: sdToday) == .moveToList(ids: ["a"], listId: inboxListId))
        #expect(sidebarDropAction(.list("work"), [sdA], today: sdToday) == nil)
    }

    @Test("a tag: added; 已完成: completed; 垃圾桶: deleted; finished tasks left alone")
    func states() {
        #expect(sidebarDropAction(.tag("y"), [sdA, sdB], today: sdToday)
            == .setTags([BatchTagChange(id: "a", tags: ["x", "y"]), BatchTagChange(id: "b", tags: ["y"])]))
        #expect(sidebarDropAction(.tag("x"), [sdA], today: sdToday) == nil)
        #expect(sidebarDropAction(.smart(.completed), [sdA, sdDone], today: sdToday) == .complete(ids: ["a"]))
        #expect(sidebarDropAction(.smart(.trash), [sdB], today: sdToday) == .trash(ids: ["b"]))
        #expect(sidebarDropAction(.smart(.completed), [sdDone], today: sdToday) == nil)
    }

    @Test("最近7天 and filters take nothing")
    func nothing() {
        #expect(sidebarDropAction(.smart(.next7), [sdA], today: sdToday) == nil)
        #expect(sidebarDropAction(.filter("f"), [sdA], today: sdToday) == nil)
    }

    @Test("the handoff: only the text of the drag it started")
    func handoff() {
        let h = DragHandoff()
        #expect(h.tasks(arriving: ["a"]) == nil)
        h.begin(.tasks(DraggedTasks(sdA, [sdA, sdB])), text: "a\nb")
        #expect(h.tasks(arriving: ["a\nb"])?.map(\.id) == ["a", "b"])
        #expect(h.tasks(arriving: ["something else"]) == nil)
        h.begin(.section(ListSection(id: "s", listId: "work", name: "s")), text: "s")
        #expect(h.tasks(arriving: ["s"]) == nil)
    }
}
