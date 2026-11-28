// 四象限 on a phone: a quadrant's page has 排序, each task gets a ≡, and
// dragging one moves it up or down in the quadrant for good (the quadrants
// switch from by-time to 自定义 order). On the demo data, quadrant 1
// (`-OTOpen matrix:quadrant`, high priority) has 评审设计稿的第二版 (due two
// days ago) above 写第四季度工作总结 (today).

import XCTest

final class MatrixSortUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = await XCUIApplication.launchOpenTodo(route: "matrix:quadrant")
    }

    @MainActor
    private func title(_ t: String) -> XCUIElement { app.staticTexts[t].firstMatch }

    @MainActor
    func testSortMovesATaskWithinTheQuadrant() {
        let early = title("评审设计稿的第二版")
        let late = title("写第四季度工作总结")
        XCTAssertTrue(early.waitForExistence(timeout: 15))
        XCTAssertLessThan(early.frame.minY, late.frame.minY)
        app.buttons["排序"].firstMatch.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        let handles = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "拖动排序"))
            .allElementsBoundByIndex
        let lateY = title("写第四季度工作总结").frame.midY
        let handle = handles.min { abs($0.frame.midY - lateY) < abs($1.frame.midY - lateY) }!
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: title("评审设计稿的第二版").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(app.buttons["排序"].waitForExistence(timeout: 5))
        XCTAssertLessThan(title("写第四季度工作总结").frame.minY, title("评审设计稿的第二版").frame.minY)
    }
}
