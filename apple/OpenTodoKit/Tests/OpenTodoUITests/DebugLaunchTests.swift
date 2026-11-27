import Foundation
import OpenTodoData
import OpenTodoDomain
import Testing
@testable import OpenTodoUI

@Test func parsesTheDebugOptions() {
    let l = DebugLaunch(arguments: [
        "/path/OpenTodo", "-NSDocumentRevisionsDebugMode", "YES",
        "-OTDatabasePath", "/tmp/x.sqlite", "-OTSeed", "demo", "-OTOpen", "list:abc", "-OTQuickAdd", "明天开会",
    ])
    #expect(l.quickAddText == "明天开会")
    #expect(l.databasePath == "/tmp/x.sqlite")
    #expect(l.seed == .demo)
    #expect(l.open == .list("abc"))
    #expect(l.snapshotPath == nil)
    #expect(l.problems.isEmpty)
}

@Test func readsTheWindowSize() {
    let l = DebugLaunch(arguments: ["app", "-OTWindowSize", "760x460", "-OTOpen", "settings:focus"])
    #expect(l.windowSize == DebugWindowSize("760x460"))
    #expect(l.windowSize?.width == 760)
    #expect(l.open?.settingsTab == .focus)
    #expect(DebugLaunch(arguments: ["app", "-OTWindowSize", "wide"]).problems.count == 1)
}

@Test func readsTheHiddenWindowsOption() {
    #expect(DebugLaunch(arguments: ["app", "-OTHiddenWindows", "yes"]).hiddenWindows)
    #expect(!DebugLaunch(arguments: ["app", "-OTHiddenWindows", "no"]).hiddenWindows)
    #expect(!DebugLaunch(arguments: ["app"]).hiddenWindows)
    #expect(DebugLaunch(arguments: ["app", "-OTHiddenWindows", "1"]).problems.count == 1)
}

@Test func readsTheTimeOfDay() {
    #expect(DebugLaunch(arguments: ["app", "-OTTime", "10:30"]).timeOfDay == 630)
    #expect(DebugLaunch(arguments: ["app", "-OTTime", "0:05"]).timeOfDay == 5)
    #expect(DebugLaunch(arguments: ["app"]).timeOfDay == nil)
    for bad in ["24:00", "10:60", "1030", "10:", "ten:30"] {
        let l = DebugLaunch(arguments: ["app", "-OTTime", bad])
        #expect(l.timeOfDay == nil && l.problems.count == 1)
    }
}

@MainActor @Test func pinsTheClockOfALaunchWithATime() throws {
    func services() throws -> AppServices {
        let db = try AppDatabase.inMemory()
        return AppServices(database: db, tokens: KeyValueTokenStore(db), reminderBackend: MemoryReminderBackend())
    }
    let pinned = AppModel.forLaunch(DebugLaunch(arguments: ["app", "-OTTime", "10:30"]), services: try services())
    #expect(pinned.clockPinned && pinned.now.minuteOfDay == 630 && pinned.today == Day.today(in: pinned.timeZone))
    #expect(!AppModel.forLaunch(DebugLaunch(arguments: ["app"]), services: try services()).clockPinned)
}

@Test func reportsWhatItCannotRead() {
    let l = DebugLaunch(arguments: ["app", "-OTSeed", "lots", "-OTOpen", "nowhere", "-OTFoo", "1", "-OTAppearance", "dark", "-OTSnapshot"])
    #expect(l.seed == nil)
    #expect(l.open == nil)
    #expect(l.appearance == .dark)
    #expect(l.problems.count == 4)
}

@Test(arguments: ["home", "smart:today", "list:a:b", "tag:工作", "filter:f1", "task:t1",
                  "calendar", "calendar:month", "timeline", "settings", "settings:account", "prefs:denied", "account:signedIn"])
func routesRoundTrip(_ text: String) {
    #expect(DebugRoute(text)?.text == text)
}

@Test(arguments: ["", "list", "list:", "home:x", "settings:a", "calendar:"])
func rejectsMalformedRoutes(_ text: String) {
    #expect(DebugRoute(text) == nil)
}

@Test func resolvesRelativePathsIntoTheTemporaryDirectory() {
    #expect(DebugLaunch.resolve("/a/b.sqlite").path == "/a/b.sqlite")
    let rel = DebugLaunch.resolve("shot/b.sqlite").path
    #expect(rel.hasSuffix("/shot/b.sqlite"))
    #expect(rel.hasPrefix(URL(fileURLWithPath: NSTemporaryDirectory()).path))
}
