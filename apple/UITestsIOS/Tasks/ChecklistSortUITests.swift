// 子任务 in order, with a finger: 排序 by the section's title gives each
// subtask a ≡ handle, dragging one moves it straight up or down; 完成 turns
// it off. On the demo task 写第四季度工作总结
// (`-OTOpen task:report`): 列出今年上线的项目, 收集各项目的数据, 写问题和教训,
// 写明年的计划, 请同事看一遍.

import XCTest

final class ChecklistSortUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = await XCUIApplication.launchOpenTodo(route: "task:report")
    }

    @MainActor
    private func item(_ title: String) -> XCUIElement {
        app.textFields.matching(NSPredicate(format: "value == %@", title)).firstMatch
    }

    @MainActor
    private var handles: [XCUIElement] {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "拖动排序")).allElementsBoundByIndex
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    @MainActor
    func testSortButtonGivesHandlesAndADragReorders() {
        let first = item("列出今年上线的项目")
        let last = item("请同事看一遍")
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        // The subtasks are at the bottom of the form.
        if !last.isHittable { app.swipeUp() }
        XCTAssertTrue(handles.isEmpty)
        let sort = app.buttons["排序"]
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        sort.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        let hs = handles
        XCTAssertEqual(hs.count, 5)
        // The last one onto the top half of the first: first.
        hs[4].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.3, thenDragTo: hs[0].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(app.buttons["排序"].waitForExistence(timeout: 5))
        XCTAssertTrue(handles.isEmpty)
        // Saved: the order comes back from the database.
        XCTAssertLessThan(item("请同事看一遍").frame.minY, item("列出今年上线的项目").frame.minY)
    }
}
