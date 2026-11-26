// The main flows on a phone, end to end through the screens: add a task by
// quick add (date, time, tag and priority typed in), see it in the list,
// complete it, find it in 已完成, rename it in its page, delete it and
// restore it from 垃圾桶; the calendar tab shows dated tasks; search finds
// a task and opens it. Each case starts on a fresh database with the demo
// data (`launchOpenTodo`).
//
// Waits are `waitForExistence` on what the step should bring up, never a
// fixed sleep.

import XCTest

final class SmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: Helpers

    /// The first element whose label contains `text` (rows combine their
    /// title, date and list into one label).
    @MainActor
    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func tapTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "tab \(name)")
        tab.tap()
    }

    /// Back to the views list of the 任务 tab, scrolled to the top (an
    /// earlier step may have left it scrolled down, 收集箱 out of sight).
    @MainActor
    private func goHome() {
        tapTab("任务")
        let home = app.navigationBars["任务"]
        let back = app.navigationBars.buttons["BackButton"]
        for _ in 0..<4 where !home.exists && back.exists {
            back.tap()
        }
        XCTAssertTrue(home.waitForExistence(timeout: 5), app.debugDescription)
        let inbox = app.staticTexts["收集箱"]
        for _ in 0..<4 where !inbox.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(inbox.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    private func openView(_ name: String) {
        goHome()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        // 已完成 and 垃圾桶 are at the end, under the tags.
        for _ in 0..<4 where !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "view \(name)")
        row.tap()
    }

    // MARK: Cases

    @MainActor
    func testAddCompleteRenameDeleteRestore() {
        app = XCUIApplication.launchOpenTodo(route: "smart:tomorrow")

        // Quick add, with everything typed in.
        let add = app.navigationBars.buttons["新建任务"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("明天下午3点开会 #冒烟 !高\n")
        let close = app.buttons["取消"]
        if close.waitForExistence(timeout: 3) { close.tap() }

        // In 明天, with its tag; its page says when.
        let row = element(containing: "开会，")
        let anyRow = row.exists ? row : element(containing: "开会")
        XCTAssertTrue(anyRow.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(anyRow.label.contains("冒烟"), anyRow.label)
        anyRow.tap()
        XCTAssertTrue(element(containing: "明天, 下午3:00").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element(containing: "高优先级").exists)

        // Complete it from its page: it shows in 已完成.
        let check = app.buttons["完成"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        check.tap()
        XCTAssertTrue(app.buttons["标记为未完成"].firstMatch.waitForExistence(timeout: 5))
        openView("已完成")
        let done = element(containing: "开会")
        XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription)

        // Rename it in its page: the caret after the old title (a tap at
        // the field's far end), the old title deleted, the new one typed.
        done.tap()
        let title = app.textFields["标题"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let old = (title.value as? String) ?? ""
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "开周会")
        XCTAssertEqual(title.value as? String, "开周会")
        // Leaving the page saves it.
        openView("已完成")
        let renamed = element(containing: "开周会")
        XCTAssertTrue(renamed.waitForExistence(timeout: 5), app.debugDescription)

        // Delete it from its page's 更多 menu.
        renamed.tap()
        let more = app.buttons["更多"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let delete = app.buttons["删除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), app.debugDescription)
        delete.tap()

        // 垃圾桶 has it; 恢复 brings it back to 已完成.
        openView("垃圾桶")
        let trashed = element(containing: "开周会")
        XCTAssertTrue(trashed.waitForExistence(timeout: 5), app.debugDescription)
        trashed.tap()
        let restore = app.buttons["恢复"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5), app.debugDescription)
        restore.tap()
        openView("已完成")
        XCTAssertTrue(element(containing: "开周会").waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testTheCalendarTabShowsDatedTasks() {
        app = XCUIApplication.launchOpenTodo()
        tapTab("日历")
        // 部门周会 is today at 10:00 in the demo data: the month's day list shows it.
        XCTAssertTrue(element(containing: "部门周会").waitForExistence(timeout: 15), app.debugDescription)
    }

    @MainActor
    func testSearchFindsATaskAndOpensIt() {
        app = XCUIApplication.launchOpenTodo()
        tapTab("搜索")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("汇报")
        let hit = element(containing: "做季度汇报的幻灯片")
        XCTAssertTrue(hit.waitForExistence(timeout: 5), app.debugDescription)
        hit.tap()
        // Its page, on the 任务 tab.
        XCTAssertTrue(app.tabBars.buttons["任务"].isSelected)
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 5), app.debugDescription)
    }
}
