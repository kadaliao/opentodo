// Interface tests on the iOS simulator (XCUITest), target
// `OpenTodoUITestsIOS`: what can only be checked with a finger — drags,
// long presses, swipes. Everything that can be said on AppModel belongs in
// the package's tests (OpenTodoUITests), which are much faster.
//
// Adding cases: a file per feature in its own folder (`Timeline/`,
// `Board/` …), a `XCTestCase` subclass, and the app started with
// `XCUIApplication.launchOpenTodo(route:)`: a new temporary database,
// filled with the demo data (`Model/DemoData.swift`: lists `work` with
// sections 进行中 / 待安排, `life`, `shopping` …; ids fixed, dates relative
// to today), opened at a `-OTOpen` route (`App/DebugLaunch.swift`). Find
// elements by their accessibility labels, which the views set in Chinese.
//
// Running them (one simulator of your own, not the shared one):
//
//     cd apple && ./scripts/generate.sh
//     xcodebuild test -project OpenTodo.xcodeproj -scheme OpenTodoUITestsIOS \
//         -destination 'platform=iOS Simulator,name=OT-<you>' -derivedDataPath .derived
//     # one class or case: -only-testing:OpenTodoUITestsIOS/TimelineDragUITests/testLongPressThenDragMovesABar

import XCTest

extension XCUIApplication {
    /// Starts the app on a fresh database with the demo data (`seed` nil:
    /// empty, as a first launch), opened at `route` (nil: where it opens).
    /// `arguments` are added after (e.g. `["-OTQuickAdd", "明天开会"]`).
    @MainActor
    @discardableResult
    static func launchOpenTodo(route: String? = nil, seed: String? = "demo", arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Relative: inside the app's temporary directory; a new one each run.
        var args = ["-OTDatabasePath", "uitest-\(UUID().uuidString)/opentodo.sqlite"]
        if let seed { args += ["-OTSeed", seed] }
        if let route { args += ["-OTOpen", route] }
        app.launchArguments = args + arguments
        app.launch()
        return app
    }
}

/// Dates as the app writes them, counted from today on the simulator's
/// clock (the demo data is relative to today too).
enum UITestDates {
    /// 11月27日 for `offset` days from today.
    static func monthDay(_ offset: Int) -> String {
        let cal = Calendar(identifier: .gregorian)
        let d = cal.date(byAdding: .day, value: offset, to: Date())!
        let c = cal.dateComponents([.month, .day], from: d)
        return "\(c.month!)月\(c.day!)日"
    }
}
