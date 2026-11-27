// The task list with a finger: a long press on a row's right end turns
// 排序 on (each row of a group in manual order gets the system's ≡ handle;
// dragging one reorders within the group; 完成 turns it off); a long press
// elsewhere on the row opens the task's menu; a tap opens the task. On the
// demo list 工作 (`-OTOpen list:work`), section 进行中: 做季度汇报的幻灯片
// (pinned, on top), 写第四季度工作总结, 部门周会, 评审设计稿的第二版,
// 报销十一月的差旅费. A row's label is “完成、<title>、<details>” (the
// checkbox's label comes first).

import XCTest

final class TaskListDragUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = await XCUIApplication.launchOpenTodo(route: "list:work")
    }

    @MainActor
    private func row(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "完成、" + title + "、")).firstMatch
    }

    @MainActor
    private var done: XCUIElement { app.navigationBars.buttons["完成"] }

    @MainActor
    private func handle(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "对完成、" + title + "、")).firstMatch
    }

    /// The right end of a row (the grip is the last 64 points of it).
    @MainActor
    private func rightEnd(of r: XCUIElement) -> XCUICoordinate {
        r.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
    }

    @MainActor
    func testLongPressOnTheRightEndSortsAndTheHandleReorders() {
        let target = row("部门周会")
        let dragged = row("报销十一月的差旅费")
        XCTAssertTrue(target.waitForExistence(timeout: 15))
        XCTAssertTrue(dragged.waitForExistence(timeout: 5))
        XCTAssertLessThan(target.frame.minY, dragged.frame.minY)
        XCTAssertFalse(handle("部门周会").exists)
        rightEnd(of: dragged).press(forDuration: 0.8)
        // 排序: handles, 完成, and no menu.
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(handle("报销十一月的差旅费").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["开始专注"].exists)
        // The last of the section onto the top half of 部门周会: before it.
        handle("报销十一月的差旅费").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        done.tap()
        XCTAssertFalse(handle("报销十一月的差旅费").waitForExistence(timeout: 2))
        // Out and back in: the list is drawn again from what was saved.
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["工作"].firstMatch.tap()
        XCTAssertTrue(row("报销十一月的差旅费").waitForExistence(timeout: 5))
        XCTAssertLessThan(row("报销十一月的差旅费").frame.minY, row("部门周会").frame.minY)
        XCTAssertGreaterThan(row("报销十一月的差旅费").frame.minY, row("写第四季度工作总结").frame.minY)
        // A tap opens the task again.
        row("部门周会").tap()
        XCTAssertTrue(app.textFields["添加子任务"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLongPressElsewhereOpensTheMenu() {
        let r = row("部门周会")
        XCTAssertTrue(r.waitForExistence(timeout: 15))
        r.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["开始专注"].waitForExistence(timeout: 5))
        XCTAssertFalse(done.exists)
    }

    @MainActor
    func testTapOpensTheTask() {
        let r = row("部门周会")
        XCTAssertTrue(r.waitForExistence(timeout: 15))
        r.tap()
        XCTAssertTrue(app.textFields["添加子任务"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTapOnTheRightEndOpensTheTask() {
        let r = row("部门周会")
        XCTAssertTrue(r.waitForExistence(timeout: 15))
        rightEnd(of: r).tap()
        XCTAssertTrue(app.textFields["添加子任务"].waitForExistence(timeout: 5))
    }
}
