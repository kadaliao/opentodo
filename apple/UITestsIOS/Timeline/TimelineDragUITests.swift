// The timeline with a finger: a long press then a move drags a bar to
// another day; a long press on its end drags the end; a long press let go
// without moving opens the task's menu. On the demo list 工作 as a
// timeline (`-OTOpen timeline:list:work`), by day: the screen starts the
// day before today, four days wide on a phone. A bar's label is
// “<title>，<first day>[到<last day>]”.

import XCTest

final class TimelineDragUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = await XCUIApplication.launchOpenTodo(route: "timeline:list:work")
    }

    @MainActor
    private func bar(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title + "，")).firstMatch
    }

    /// One day on the timeline by day (`TimelineMetrics.dayWidth`).
    private let day = 96.0

    @MainActor
    func testLongPressThenDragMovesABar() {
        // 做季度汇报的幻灯片 is tomorrow; a day back onto today.
        let b = bar("做季度汇报的幻灯片")
        XCTAssertTrue(b.waitForExistence(timeout: 15))
        XCTAssertEqual(b.label, "做季度汇报的幻灯片，\(UITestDates.monthDay(1))")
        let start = b.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.8, thenDragTo: start.withOffset(CGVector(dx: -day, dy: 0)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        let moved = bar("做季度汇报的幻灯片")
        XCTAssertTrue(moved.waitForExistence(timeout: 5))
        XCTAssertEqual(moved.label, "做季度汇报的幻灯片，\(UITestDates.monthDay(0))")
    }

    @MainActor
    func testLongPressOnTheEndDragsTheEnd() {
        // 部门周会 is today, one day; its right end a day on.
        let b = bar("部门周会")
        XCTAssertTrue(b.waitForExistence(timeout: 15))
        let end = b.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5))
        end.press(forDuration: 0.8, thenDragTo: end.withOffset(CGVector(dx: day, dy: 0)),
                  withVelocity: .slow, thenHoldForDuration: 0.3)
        let longer = bar("部门周会")
        XCTAssertTrue(longer.waitForExistence(timeout: 5))
        XCTAssertEqual(longer.label, "部门周会，\(UITestDates.monthDay(0))到\(UITestDates.monthDay(1))")
    }

    @MainActor
    func testLongPressWithoutMovingOpensTheMenu() {
        let b = bar("做季度汇报的幻灯片")
        XCTAssertTrue(b.waitForExistence(timeout: 15))
        b.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        // The bar stayed where it was.
        XCTAssertEqual(bar("做季度汇报的幻灯片").label, "做季度汇报的幻灯片，\(UITestDates.monthDay(1))")
    }
}
