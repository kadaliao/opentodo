// AppSettings, ViewPrefs, TimelinePrefs and LocalSettings. Includes
// pin_sort_test's "view preferences read what earlier versions stored" and
// the AppSettings half of task_defaults_test's round trip.

import Foundation
import Testing
@testable import OpenTodoData

@Suite struct SettingsTests {
    @Test("round trip, and bad or missing values fall back")
    func appSettings() throws {
        let d = TaskDefaults(timedReminders: [-30], allDayReminders: [540, -900], spanMinutes: 90)
        let back = AppSettings(json: AppSettings(defaults: d).json).defaults
        #expect(back == d)
        #expect(AppSettings(json: .fields([])).defaults == .standard)
        #expect(AppSettings(json: .fields([])).snoozeMinutes == 15)

        // The JSON the Flutter version writes, key for key.
        #expect(AppSettings(defaults: d, snoozeMinutes: 10).json.encoded()
            == #"{"defaults":{"timedReminders":[-30],"allDayReminders":[540,-900],"spanMinutes":90},"snoozeMinutes":10}"#)
        let odd = AppSettings(json: try JSONValue.decode(#"{"defaults":{"timedReminders":"x","spanMinutes":-5,"allDayReminders":[540,"y"]},"snoozeMinutes":0}"#))
        #expect(odd.defaults.timedReminders == [0])
        #expect(odd.defaults.allDayReminders == [540])
        #expect(odd.defaults.spanMinutes == 60)
        #expect(odd.snoozeMinutes == 15)
        #expect(AppSettings(json: try JSONValue.decode(#"{"snoozeMinutes":10.0}"#)).snoozeMinutes == 10)
    }

    @Test("view preferences read what earlier versions stored")
    func viewPrefs() throws {
        let list = ViewRef.list("w")
        #expect(ViewPrefs(json: .string("board")).layout == .board)
        #expect(ViewPrefs(json: .string("board")).sortIn(list) == .manual)
        let p = ViewPrefs(json: try JSONValue.decode(#"{"layout":"list","sort":"due"}"#))
        #expect(p.layout == .list && p.sortIn(list) == .due && p.groupingIn(list) == .sections)
        #expect(ViewPrefs(json: try JSONValue.decode(#"{"layout":"gallery","sort":"mood","group":"x"}"#)).isDefault)
        #expect(ViewPrefs(json: .int(42)).isDefault)
        // A choice a view doesn't offer falls back to its default.
        let today = ViewRef.smart(.today)
        #expect(p.sortIn(today) == .due)
        #expect(ViewPrefs(sort: .manual, grouping: .sections).groupingIn(today) == .date)
        #expect(ViewPrefs(sort: .manual).sortIn(today) == .due)
        let round = ViewPrefs(json: ViewPrefs(sort: .tag, grouping: .priority).json)
        #expect(round.grouping == .priority && round.sort == .tag)
        #expect(ViewPrefs().sortIn(.smart(.trash)) == nil)
    }

    @Test("layouts: a board only for a list, a timeline where tasks can be arranged")
    func layouts() {
        #expect(ViewPrefs(layout: .board).layoutIn(.list("w")) == .board)
        #expect(ViewPrefs(layout: .board).layoutIn(.smart(.inbox)) == .board)
        #expect(ViewPrefs(layout: .board).layoutIn(.smart(.today)) == .list)
        #expect(ViewPrefs(layout: .timeline).layoutIn(.tag("x")) == .timeline)
        #expect(ViewPrefs(layout: .timeline).layoutIn(.smart(.completed)) == .list)
        #expect(viewPrefsKey(.list("w")) == "w")
        #expect(viewPrefsKey(.smart(.inbox)) == inboxListId)
        #expect(viewPrefsKey(.smart(.today)) == "smart:today")
        #expect(ViewPrefs(layout: .board, grouping: .tag).json.encoded() == #"{"layout":"board","group":"tag"}"#)
    }

    @Test("timeline preferences")
    func timeline() throws {
        #expect(TimelinePrefs().json.encoded() == #"{"scale":"day","showDone":false}"#)
        let p = TimelinePrefs(scale: .week, showDone: true, trayOpen: false)
        #expect(p.json.encoded() == #"{"scale":"week","showDone":true,"trayOpen":false}"#)
        #expect(TimelinePrefs(json: p.json) == p)
        #expect(TimelinePrefs(json: try JSONValue.decode(#"{"scale":"decade","showDone":1}"#)) == TimelinePrefs())
    }

    @Test("stored, read back, damaged ones as the defaults")
    @MainActor
    func store() throws {
        let db = try AppDatabase.inMemory()
        try db.setValueNow(Keys.listPrefs, #"{"w":"board","smart:today":{"layout":"timeline","group":"list"}}"#)
        try db.setValueNow(Keys.timelinePrefs, "nonsense")
        try db.setValueNow(Keys.settings, #"{"snoozeMinutes":5}"#)
        let s = LocalSettings(db)
        #expect(s.viewPrefs(for: .list("w")).layout == .board)
        #expect(s.viewPrefs(for: .smart(.today)).grouping == .list)
        #expect(s.timelinePrefs == TimelinePrefs())
        #expect(s.settings.snoozeMinutes == 5)
        #expect(s.calendarPrefs == CalendarPrefs())

        // The default is stored as no choice; a view back to defaults goes.
        s.setSort(.list("w"), .due)
        s.setGrouping(.list("w"), .sections)
        #expect(s.viewPrefs(for: .list("w")) == ViewPrefs(layout: .board, sort: .due))
        s.setSort(.smart(.today), .due)
        s.setLayout(.smart(.today), .list)
        s.setGrouping(.smart(.today), .date)
        #expect(try db.getValueNow(Keys.listPrefs) == #"{"w":{"layout":"board","sort":"due"}}"#)

        s.setTimelinePrefs(TimelinePrefs(scale: .month))
        s.setDefaults(TaskDefaults(timedReminders: [-5]))
        s.setSnoozeMinutes(30)
        var cal = CalendarPrefs()
        cal.showLunar = false
        s.setCalendarPrefs(cal)
        #expect(s.saveError == nil)
        #expect(s.defaultsProvider().timedReminders == [-5])
        #expect(s.current.snoozeMinutes == 30)

        let again = LocalSettings(db)
        #expect(again.timelinePrefs.scale == .month)
        #expect(again.settings == AppSettings(defaults: TaskDefaults(timedReminders: [-5]), snoozeMinutes: 30))
        #expect(again.calendarPrefs.showLunar == false)
        #expect(again.viewPrefs == s.viewPrefs)
    }

    @Test("the quadrants, the focus settings and a running timer are kept")
    @MainActor
    func efficiency() throws {
        let db = try AppDatabase.inMemory()
        try db.setValueNow(Keys.matrixPrefs, "nonsense")
        let s = LocalSettings(db)
        #expect(s.matrixPrefs == .standard)
        #expect(s.focusSettings == .standard)
        #expect(s.focusTimer == nil)

        var matrix = MatrixPrefs.standard
        matrix.quadrants[0].name = "马上做"
        s.setMatrixPrefs(matrix)
        s.setFocusSettings(FocusSettings(pomodoroMinutes: 30, autoStartNext: true))
        let start = 1_000_000
        var timer = FocusTimer(settings: s.focusSettings)
        timer.start(at: start, taskId: "t")
        s.setFocusTimer(timer)
        #expect(s.saveError == nil)
        #expect(try db.getValueNow(Keys.matrixPrefs)?.contains("马上做") == true)
        #expect(try db.getValueNow(Keys.focusSettings).map(FocusSettings.decode)?.pomodoroMinutes == 30)

        // The app is killed and opened 31 minutes later: the pomodoro ran out
        // at 30, and the break started then on its own.
        let again = LocalSettings(db)
        #expect(again.matrixPrefs.quadrants[0].name == "马上做")
        #expect(again.focusSettings.autoStartNext)
        var back = try #require(again.focusTimer)
        #expect(back == timer)
        let finished = back.tick(at: start + 31 * 60_000)
        #expect(finished.map(\.duration) == [30 * 60])
        #expect(finished.first?.taskId == "t")
        #expect(back.isRunning)

        again.setFocusTimer(nil)
        #expect(try db.getValueNow(Keys.focusTimer) == nil)
    }
}
