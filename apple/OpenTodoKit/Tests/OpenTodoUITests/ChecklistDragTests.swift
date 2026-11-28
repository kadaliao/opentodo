// Dragging a subtask by its handle (macOS): straight up or down, past the
// middles of the rows it goes by.

import CoreGraphics
import Foundation
import Testing
@testable import OpenTodoUI

@Suite("Checklist drag")
struct StackDragTests {
    private let rows: [CGFloat] = [40, 40, 40, 40]

    @Test("past a row's middle it takes that row's place; the rows passed make room")
    func down() {
        let d = StackDrag(from: 0, dy: 41, heights: rows)
        #expect(d.position == 1)
        #expect(StackDrag(from: 0, dy: 39, heights: rows).position == 0)
        #expect(d.shifts(1) == -40 && d.shifts(2) == 0 && d.shifts(0) == 0)
        #expect(d.moveIndex == 2)
    }

    @Test("up to the top")
    func up() {
        let d = StackDrag(from: 3, dy: -125, heights: rows)
        #expect(d.position == 0)
        #expect(d.shifts(0) == 40 && d.shifts(2) == 40 && d.shifts(3) == 0)
        #expect(d.moveIndex == 0)
    }

    @Test("let go where it was: nothing to write")
    func stays() {
        #expect(StackDrag(from: 2, dy: 10, heights: rows).moveIndex == nil)
    }

    @Test("kept within the stack")
    func clamp() {
        #expect(StackDrag.clamp(-500, from: 1, heights: rows) == -60)
        #expect(StackDrag.clamp(500, from: 1, heights: rows) == 100)
        // As far as it goes, it takes the first / last place.
        #expect(StackDrag(from: 1, dy: StackDrag.clamp(-500, from: 1, heights: rows), heights: rows).position == 0)
        #expect(StackDrag(from: 1, dy: StackDrag.clamp(500, from: 1, heights: rows), heights: rows).position == 3)
        #expect(StackDrag.clamp(15, from: 1, heights: rows) == 15)
    }
}

// MARK: - 四象限: a task dragged by its handle within its quadrant

import OpenTodoDomain

@Suite("Matrix reorder")
struct MatrixReorderTests {
    private let now = LocalDateTime(Day(2026, 11, 28), minute: 600)

    private func t(_ id: String, _ p: Priority, due: Int, order: Double) -> TodoTask {
        TodoTask(id: id, listId: "L", title: id, priority: p, dueDate: Day(2026, 11, 28) + due, sortOrder: order)
    }

    @Test("the first time: every quadrant keeps the order it showed, the moved one takes its place")
    func first() {
        // By time: b (today), a (tomorrow); x, y in another quadrant, shown y, x.
        let tasks = [t("a", .high, due: 1, order: 1), t("b", .high, due: 0, order: 2),
                     t("x", .medium, due: 3, order: 3), t("y", .medium, due: 2, order: 4)]
        let r = matrixReorder("a", to: 0, in: 0, tasks: tasks, prefs: MatrixPrefs(), now: now)
        #expect(r.switchToManual)
        var after = tasks
        for i in after.indices { if let o = r.orders[after[i].id] { after[i].sortOrder = o } }
        let cells = matrixCells(after, prefs: MatrixPrefs(manualOrder: true), now: now)
        #expect(cells[0].tasks.map(\.id) == ["a", "b"])
        #expect(cells[1].tasks.map(\.id) == ["y", "x"])
    }

    @Test("already 自定义: only the quadrant moved in changes")
    func later() {
        let tasks = [t("a", .high, due: 1, order: 1), t("b", .high, due: 0, order: 2),
                     t("x", .medium, due: 3, order: 4), t("y", .medium, due: 2, order: 3)]
        let r = matrixReorder("b", to: 0, in: 0, tasks: tasks, prefs: MatrixPrefs(manualOrder: true), now: now)
        #expect(!r.switchToManual)
        #expect(Set(r.orders.keys).isSubset(of: ["a", "b"]))
        #expect(r.orders["b"]! < r.orders["a"]!)
    }
}

@Suite("Drop places across a rebuilt row")
@MainActor
struct DropSlotOwnerTests {
    @Test("the old row going away doesn't take the new row's place with it")
    func rebuilt() {
        let c = DragController()
        let old = UUID(), new = UUID()
        let kind = DropSlotKind.taskArea(GroupDrop(.order), index: 0)
        c.setSlot("row-a", frame: CGRect(x: 0, y: 0, width: 100, height: 40), kind: kind, clips: [], owner: old)
        c.setSlot("row-a", frame: CGRect(x: 0, y: 0, width: 100, height: 40), kind: kind, clips: [], owner: new)
        c.removeSlot("row-a", owner: old)
        #expect(c.visibleSlots.map(\.id) == ["row-a"])
        c.removeSlot("row-a", owner: new)
        #expect(c.visibleSlots.isEmpty)
    }
}
