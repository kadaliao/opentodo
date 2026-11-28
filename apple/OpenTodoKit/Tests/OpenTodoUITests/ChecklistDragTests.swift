// Dragging a subtask by its handle (macOS): straight up or down, past the
// middles of the rows it goes by.

import CoreGraphics
import Testing
@testable import OpenTodoUI

@Suite("Checklist drag")
struct ChecklistDragTests {
    private let rows: [CGFloat] = [40, 40, 40, 40]

    @Test("past a row's middle it takes that row's place; the rows passed make room")
    func down() {
        let d = ChecklistDrag(from: 0, dy: 41, heights: rows)
        #expect(d.position == 1)
        #expect(ChecklistDrag(from: 0, dy: 39, heights: rows).position == 0)
        #expect(d.shifts(1) == -40 && d.shifts(2) == 0 && d.shifts(0) == 0)
        #expect(d.moveIndex == 2)
    }

    @Test("up to the top")
    func up() {
        let d = ChecklistDrag(from: 3, dy: -125, heights: rows)
        #expect(d.position == 0)
        #expect(d.shifts(0) == 40 && d.shifts(2) == 40 && d.shifts(3) == 0)
        #expect(d.moveIndex == 0)
    }

    @Test("let go where it was: nothing to write")
    func stays() {
        #expect(ChecklistDrag(from: 2, dy: 10, heights: rows).moveIndex == nil)
    }

    @Test("kept within the stack")
    func clamp() {
        #expect(ChecklistDrag.clamp(-500, from: 1, heights: rows) == -60)
        #expect(ChecklistDrag.clamp(500, from: 1, heights: rows) == 100)
        // As far as it goes, it takes the first / last place.
        #expect(ChecklistDrag(from: 1, dy: ChecklistDrag.clamp(-500, from: 1, heights: rows), heights: rows).position == 0)
        #expect(ChecklistDrag(from: 1, dy: ChecklistDrag.clamp(500, from: 1, heights: rows), heights: rows).position == 3)
        #expect(ChecklistDrag.clamp(15, from: 1, heights: rows) == 15)
    }
}
