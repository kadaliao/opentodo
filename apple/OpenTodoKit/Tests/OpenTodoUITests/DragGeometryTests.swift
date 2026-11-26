// The drag pieces on their own: the hit test, the hints, scrolling at the
// edges, the controller's run of a drag, and the board's small helpers.

import CoreGraphics
import OpenTodoDomain
import SwiftUI
import Testing
@testable import OpenTodoUI

private let L = "L"

private func t(_ id: String, _ order: Double, section: String? = nil, pinned: Bool = false, status: TaskStatus = .open) -> TodoTask {
    TodoTask(id: id, listId: L, sectionId: section, title: id, status: status, pinnedAt: pinned ? 1 : nil, sortOrder: order)
}

private func s(_ id: String, _ order: Double) -> ListSection { ListSection(id: id, listId: L, name: id, sortOrder: order) }

private let a = t("a", 0), b = t("b", 1024), c = t("c", 2048)
private let manual = GroupDrop(.section(listId: L, sectionId: nil), tasks: [a, b, c], manual: true)

private func rows(_ group: GroupDrop) -> [DropSlot] {
    group.tasks.enumerated().map { i, task in
        DropSlot(id: task.id, frame: CGRect(x: 0, y: CGFloat(i) * 40, width: 200, height: 40), kind: .taskRow(group, index: i))
    }
}

@Test func aRowTakesBeforeOnItsTopHalfAndAfterOnItsBottomHalf() {
    let x = t("x", 5000, section: "other")
    let item = DragItem.tasks(DraggedTasks(x))
    let top = resolveDrop(item, at: CGPoint(x: 10, y: 45), in: rows(manual))
    #expect(top?.action == .tasks(manual, index: 1))
    #expect(top?.indicator == .line(CGPoint(x: 0, y: 40), CGPoint(x: 200, y: 40)))
    let bottom = resolveDrop(item, at: CGPoint(x: 10, y: 75), in: rows(manual))
    #expect(bottom?.action == .tasks(manual, index: 2))
    #expect(bottom?.indicator == .line(CGPoint(x: 0, y: 80), CGPoint(x: 200, y: 80)))
    // Nothing there.
    #expect(resolveDrop(item, at: CGPoint(x: 10, y: 500), in: rows(manual)) == nil)
    // Dropped: lands between a and b.
    guard case .tasks(let plan)? = top?.outcome(for: item) else { Issue.record("no plan"); return }
    #expect(plan.ids == ["x"])
    #expect(plan.orders == ["x": 512])
}

@Test func lettingGoWhereItWasDoesNothing() {
    let item = DragItem.tasks(DraggedTasks(b))
    let hover = resolveDrop(item, at: CGPoint(x: 10, y: 45), in: rows(manual))
    #expect(hover?.indicator != DropIndicator.none)
    #expect(hover?.outcome(for: item) == nil)
}

@Test func theSmallestPlaceWinsAndSectionsAndTasksDontMix() {
    let area = DropSlot(id: "area", frame: CGRect(x: 0, y: 0, width: 300, height: 300), kind: .taskArea(manual, index: 3))
    let column = DropSlot(id: "col", frame: CGRect(x: 0, y: 0, width: 300, height: 300),
                          kind: .section(s("s1", 0), among: [s("s1", 0), s("s2", 1)], axis: .horizontal))
    let slots = rows(manual) + [area, column]
    let x = DragItem.tasks(DraggedTasks(t("x", 9, section: "o")))
    #expect(resolveDrop(x, at: CGPoint(x: 10, y: 10), in: slots)?.slotId == "a")
    let hover = resolveDrop(x, at: CGPoint(x: 250, y: 250), in: slots)
    #expect(hover?.slotId == "area")
    #expect(hover?.indicator == .area(area.frame))
    #expect(resolveDrop(.section(s("s2", 1)), at: CGPoint(x: 10, y: 10), in: slots)?.slotId == "col")
}

@Test func finishedOrTrashedTasksDontDrop() {
    let done = t("d", 1, section: "o", status: .done)
    #expect(resolveDrop(.tasks(DraggedTasks(done)), at: CGPoint(x: 1, y: 1), in: rows(manual)) == nil)
    var trashed = t("t", 1, section: "o")
    trashed.trashedAt = 1
    #expect(!manual.accepts(trashed))
    // Another list's task doesn't go into this list's section.
    var other = t("o", 1)
    other.listId = "M"
    #expect(!manual.accepts(other))
}

@Test func outOfManualOrderOnlyAnotherGroupsTasksDropAndTheGroupLightsUp() {
    let group = GroupDrop(.priority(.high), tasks: [a], manual: false)
    var high = t("h", 1)
    high.priority = .high
    #expect(resolveDrop(.tasks(DraggedTasks(high)), at: CGPoint(x: 1, y: 1), in: rows(group)) == nil)
    let hover = resolveDrop(.tasks(DraggedTasks(b)), at: CGPoint(x: 1, y: 1), in: rows(group))
    #expect(hover?.indicator == .group(.priority(.high)))
    #expect(hover?.outcome(for: .tasks(DraggedTasks(b))) == .tasks(TaskDropPlan(ids: ["b"], target: .priority(.high), orders: [:])))
}

@Test func onlyTheDraggedTasksThatFitGo() {
    // A drag of an open and a finished task moves only the open one.
    let done = t("d", 1, section: "o", status: .done)
    let x = t("x", 2, section: "o")
    let plan = manual.plan(DraggedTasks(x, [done, x]), at: 0)
    #expect(plan?.ids == ["x"])
}

@Test func pinnedTasksMoveAmongThePinned() {
    let p = t("p", 100, pinned: true)
    let group = GroupDrop(.section(listId: L, sectionId: nil), tasks: [p, a, b], manual: true)
    // An unpinned one dropped above the pinned one lands right after them.
    let plan = group.plan(DraggedTasks(b), at: 0)
    #expect(plan?.orders == ["b": -1024])
    // A pinned one dropped among the others stays last of the pinned.
    let q = t("q", 5, section: "o", pinned: true)
    #expect(group.plan(DraggedTasks(q), at: 3)?.orders == ["q": 1124])
}

@Test func aSectionGoesBeforeOrAfterAnotherButNoLineWhereItWouldStay() {
    let s1 = s("s1", 0), s2 = s("s2", 1024), s3 = s("s3", 2048)
    let among = [s1, s2, s3]
    let slots = among.enumerated().map { i, sec in
        DropSlot(id: sec.id, frame: CGRect(x: CGFloat(i) * 100, y: 0, width: 100, height: 400), kind: .section(sec, among: among, axis: .horizontal))
    }
    // s1 over the left half of s2: it's already there.
    let stay = resolveDrop(.section(s1), at: CGPoint(x: 120, y: 50), in: slots)
    #expect(stay?.indicator == DropIndicator.none)
    #expect(stay?.outcome(for: .section(s1)) == nil)
    // s1 over the right half of s3: to the end.
    let end = resolveDrop(.section(s1), at: CGPoint(x: 280, y: 50), in: slots)
    #expect(end?.indicator == .line(CGPoint(x: 300, y: 0), CGPoint(x: 300, y: 400)))
    #expect(end?.outcome(for: .section(s1)) == .sections(["s1": 3072]))
    // Not onto itself, nor another list's.
    #expect(resolveDrop(.section(s1), at: CGPoint(x: 50, y: 50), in: slots) == nil)
    var foreign = s("f", 0)
    foreign.listId = "M"
    #expect(resolveDrop(.section(foreign), at: CGPoint(x: 150, y: 50), in: slots) == nil)
}

@Test func sectionsMoveByOneFromTheMenu() {
    let among = [s("s1", 0), s("s2", 1024), s("s3", 2048)]
    #expect(planSectionShift(among, "s2", by: -1) == ["s2": -1024])
    #expect(planSectionShift(among, "s2", by: 1) == ["s2": 3072])
    #expect(planSectionShift(among, "s1", by: -1).isEmpty)
    #expect(planSectionShift(among, "s3", by: 1).isEmpty)
    #expect(planSectionMove(among, "s1", to: 1).isEmpty)
    #expect(SectionMenuEntry.entries(index: 0, count: 3) == [.rename, .forward, .delete])
    #expect(SectionMenuEntry.entries(index: 1, count: 3) == [.rename, .back, .forward, .delete])
    #expect(SectionMenuEntry.entries(index: 2, count: 3) == [.rename, .back, .delete])
    #expect(SectionMenuEntry.back.label(horizontal: true) == "左移")
    #expect(SectionMenuEntry.forward.label(horizontal: false) == "下移")
}

@Test func sectionNamesAreTrimmedAndNotEmpty() {
    #expect(sectionName("  进行中\n") == "进行中")
    #expect(sectionName("   ") == nil)
}

@Test func scrollingSpeedsUpTowardTheEdges() {
    let viewport = CGRect(x: 0, y: 100, width: 300, height: 400)
    #expect(edgeScrollStep(CGPoint(x: 150, y: 300), in: viewport, axis: .vertical) == 0)
    #expect(edgeScrollStep(CGPoint(x: 150, y: 100), in: viewport, axis: .vertical) == -14)
    #expect(edgeScrollStep(CGPoint(x: 150, y: 128), in: viewport, axis: .vertical) == -7)
    #expect(edgeScrollStep(CGPoint(x: 150, y: 500), in: viewport, axis: .vertical) == 14)
    // Over the header above it: full speed; far above, or beside it: none.
    #expect(edgeScrollStep(CGPoint(x: 150, y: 80), in: viewport, axis: .vertical) == -14)
    #expect(edgeScrollStep(CGPoint(x: 150, y: 20), in: viewport, axis: .vertical) == 0)
    #expect(edgeScrollStep(CGPoint(x: 400, y: 120), in: viewport, axis: .vertical) == 0)
    #expect(edgeScrollStep(CGPoint(x: 290, y: 300), in: viewport, axis: .horizontal) > 0)
    #expect(clampedScrollOffset(10, by: -14, content: 1000, viewport: 400) == 0)
    #expect(clampedScrollOffset(590, by: 14, content: 1000, viewport: 400) == 600)
    #expect(clampedScrollOffset(0, by: 14, content: 300, viewport: 400) == 0)
}

@Test func theControllerRunsADrag() {
    var dropped: [DropOutcome] = []
    let drag = DragController { dropped.append($0) }
    for slot in rows(manual) { drag.setSlot(slot.id, frame: slot.frame, kind: slot.kind, clips: []) }
    let x = t("x", 5000, section: "o")
    // Moving before a drag starts does nothing.
    drag.move(to: CGPoint(x: 10, y: 10))
    #expect(drag.hover == nil)

    drag.begin(.tasks(DraggedTasks(x)))
    #expect(!drag.isDragged("x")) // not over the space yet
    drag.move(to: CGPoint(x: 10, y: 10))
    #expect(drag.isDragged("x"))
    #expect(drag.hover?.action == .tasks(manual, index: 0))
    drag.leave()
    #expect(drag.hover == nil)
    #expect(!drag.isDragged("x"))
    #expect(drag.drop(at: CGPoint(x: 10, y: 115)))
    #expect(dropped == [.tasks(TaskDropPlan(ids: ["x"], target: manual.target, orders: ["x": 3072]))])
    #expect(drag.item == nil && drag.hover == nil)
}

@Test func placesAreCutToTheirScrollViews() {
    let drag = DragController()
    drag.setRegion("column", frame: CGRect(x: 0, y: 40, width: 200, height: 100), axis: .vertical, clips: []) { _ in }
    drag.setSlot("hidden", frame: CGRect(x: 0, y: 0, width: 200, height: 40), kind: .taskRow(manual, index: 0), clips: ["column"])
    drag.setSlot("half", frame: CGRect(x: 0, y: 120, width: 200, height: 40), kind: .taskRow(manual, index: 1), clips: ["column"])
    drag.setSlot("head", frame: CGRect(x: 0, y: 0, width: 200, height: 40), kind: .taskArea(manual, index: 0), clips: [])
    let visible = Dictionary(uniqueKeysWithValues: drag.visibleSlots.map { ($0.id, $0.frame) })
    #expect(visible["hidden"] == nil)
    #expect(visible["half"] == CGRect(x: 0, y: 120, width: 200, height: 20))
    #expect(visible["head"] == CGRect(x: 0, y: 0, width: 200, height: 40))
    drag.removeSlot("head")
    #expect(drag.visibleSlots.count == 1)
}

@Test func draggedTasksGoTogetherOnlyWhenTheLeadIsPicked() {
    #expect(DraggedTasks(a, picked: [a, b]).all.map(\.id) == ["a", "b"])
    #expect(DraggedTasks(c, picked: [a, b]).all.map(\.id) == ["c"])
    #expect(DraggedTasks(a, picked: [a]).count == 1)
}

@Test func aFinishedSectionTakesNoDrops() {
    #expect(GroupDrop(TaskSection(id: "done", title: "已完成", tasks: [], target: .order, finished: true)) == nil)
    #expect(GroupDrop(TaskSection(id: "later", title: "以后", tasks: [])) == nil)
}

@Test func theBoardsLayoutAndOrder() {
    #expect(BoardLayout.columnWidth(for: 390) == 319)
    #expect(BoardLayout.columnWidth(for: 1200) == 272)
    #expect(BoardLayout.columnWidth(for: 0) == 272)
    let sections = [s("s1", 0), s("s2", 1024)]
    var done = t("d", 0, section: "s1", status: .done)
    done.completedAt = 5
    let columns = boardColumns(L, [t("x", 0), t("y", 0, section: "s1"), t("z", 1, section: "s1"), done], sections)
    #expect(columns.map(\.group.title) == ["未分组", "s1", "s2"])
    #expect(BoardLayout.taskOrder(columns) == ["x", "y", "z", "d"])
    #expect(BoardLayout.sections(columns).map(\.id) == ["s1", "s2"])
    #expect(BoardLayout.picked(columns, BoardSelection(open: "x", picked: ["z", "x", "d"])).map(\.id) == ["x", "z"])
    #expect(BoardLayout.picked(columns, BoardSelection(open: "x")).isEmpty)
    #expect(BoardLayout.drop(columns[1], listId: L, sort: .priority) == GroupDrop(.section(listId: L, sectionId: "s1"), tasks: columns[1].group.tasks, manual: false))
    #expect(BoardLayout.key(columns[0]) == "none")
}

@Test func selectionFollowsPickingOrTheOpenCard() {
    #expect(BoardSelection(open: "a").isSelected("a"))
    #expect(!BoardSelection(open: "a", picked: ["b"]).isSelected("a"))
    #expect(BoardSelection(open: "a", picked: ["b"]).isSelected("b"))
    #expect(!BoardSelection(open: "a", picking: true).isSelected("a"))
}

@Test func checklistProgressCountsEachTasksItems() {
    let items = [
        ChecklistItem(id: "1", taskId: "a", done: true),
        ChecklistItem(id: "2", taskId: "a"),
        ChecklistItem(id: "3", taskId: "b", deletedAt: 1),
    ]
    #expect(ChecklistProgress.of(items) == ["a": ChecklistProgress(done: 1, total: 2)])
}

@Test func theBoardDebugRoute() {
    #expect(DebugRoute("board:line") == .board("line"))
    #expect(DebugRoute("board:line")?.text == "board:line")
    #expect(DebugRoute("board:") == nil)
    #expect(BoardDemo.Scene.allCases.count == 13)
}
