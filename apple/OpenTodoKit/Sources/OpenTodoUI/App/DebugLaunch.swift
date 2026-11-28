// Debug-build launch arguments (docs/apple.md §4), for screenshots and UI
// tests. The app shell passes `DebugLaunch.current` only in Debug builds;
// Release builds ignore all of this.
//
//     -OTDatabasePath <file>   open this database instead of the real one
//     -OTSeed demo             fill it with demo data first
//     -OTOpen <route>          open straight into a screen (routes below)
//     -OTAppearance dark       light or dark, whatever the system uses
//     -OTQuickAdd <text>       type this into the quick-add field (on a phone,
//                              in the 新建任务 sheet), to see its highlighting
//     -OTWindowSize 760x460    macOS: the main window's content size (not the
//                              size the window had last time)
//     -OTInterfaceSize large   macOS: 界面大小 for this run (small, standard,
//                              large, extraLarge), whatever is stored
//     -OTHiddenWindows yes     macOS: every window the app opens (the main
//                              one, Settings, popovers, sheets, panels) goes
//                              behind the desktop picture, where nobody sees
//                              it but screencapture -l and ScreenCaptureKit
//                              still capture it (scripts/shot.sh does this)
//     -OTSnapshot <file.png>   macOS: once the window is up, draw it into a
//                              PNG and quit (screenshots without the screen
//                              recording permission; see scripts/shot.sh)
//
// File paths may be absolute or relative. A relative one is inside the
// app's temporary directory (`resolve(_:)`): on macOS the app is
// sandboxed and can only write inside its container, so the scripts pass a
// bare name and look for the file under
// ~/Library/Containers/com.liaoxingyi.opentodo.dev/Data/tmp/.
//
// Routes are `<kind>` or `<kind>:<argument>`, the kinds following the Dart
// `ViewRef.toString()` names where there is one:
//
//     home                     the default screen
//     smart:<kind>             smart:today, smart:tomorrow, smart:next7,
//                              smart:inbox, smart:completed, smart:trash
//     list:<id>  tag:<name>  filter:<id>
//     task:<id>                a task's detail
//     calendar[:<mode>]        calendar, calendar:month, calendar:week …
//     calendar-demo[:<state>]  the calendar on in-memory demo data, opened on
//                              a `CalendarDemoState` (month, week, day,
//                              threeDays, multiWeek, year, agenda, picking,
//                              card, new, arrange)
//     timeline
//     timeline:<scene>         the timeline on demo data: day, week, month,
//                              tray, today, inbox, picked, done
//                              (TimelineDemo.Scene)
//     timeline:<view route>    that view of the app as a timeline:
//                              timeline:list:work, timeline:smart:today
//     settings[:<tab>]         the Settings window (macOS), on a tab: general,
//                              tasks, notifications, focus, quickAdd, account, about
//     schedule:<state>         the date dialog in a given state
//                              (Schedule/ScheduleDebug.swift)
//     batch:<state>            the batch actions (Batch/BatchDebug.swift)
//     system:<state>           macOS menu bar window / quick-add panel / their
//                              settings, in the window (System/SystemDebug.swift)
//     search[:<query>]         search (OpenTodoUI/Search/SearchDebug.swift)
//     list-editor:<id>[:<tab>] the list editor on list <id> (`new` for 添加清单),
//                              on a tab: symbol, emoji, custom (Tasks/ListEditor.swift)
//     filter-editor:<state>    the filter editor: new, simple, advanced, legacy,
//                              range, delete (same file)
//     board:<scene>            the board / drag demo (Board/BoardDemo.swift)
//     habits | focus | countdowns | matrix [:<state>]
//                              the efficiency modules with demo data
//                              (Efficiency/EfficiencyDebug.swift)
//     prefs:<state>            设置 in a given state, on demo objects
//     account:<state>          登录 / 账号 in a given state
//                              (both: Settings/SettingsDebug.swift)
//     selftest:<name>          runs a check on the real services and quits
//                              (Settings/ServicesSelfTest.swift)
//
// To add a screen: add a case, parse it in `init?(_:)`, print it in
// `text`, and handle it where the root view applies `DebugLaunch.open`.

import Foundation

public struct DebugLaunch: Sendable, Hashable {
    public var databasePath: String?
    public var seed: DebugSeed?
    public var open: DebugRoute?
    public var snapshotPath: String?
    public var appearance: DebugAppearance?
    public var quickAddText: String?
    public var windowSize: DebugWindowSize?
    public var interfaceSize: InterfaceSize?
    public var hiddenWindows = false
    /// `-OTTime HH:MM`: the app's clock stands still at that time today
    /// (screenshots that shouldn't depend on when they're taken).
    public var timeOfDay: Int?
    /// Arguments that were given but not understood, for a log line.
    public var problems: [String] = []

    public init(databasePath: String? = nil, seed: DebugSeed? = nil, open: DebugRoute? = nil, snapshotPath: String? = nil) {
        self.databasePath = databasePath
        self.seed = seed
        self.open = open
        self.snapshotPath = snapshotPath
    }

    /// Reads the `-OT…` options out of a process's arguments; everything
    /// else (Xcode's own `-NS…` options and so on) is left alone.
    public init(arguments: [String]) {
        var i = arguments.startIndex
        while i < arguments.endIndex {
            let name = arguments[i]
            guard name.hasPrefix("-OT") else { i += 1; continue }
            let value = arguments.index(after: i) < arguments.endIndex ? arguments[i + 1] : nil
            i += value == nil ? 1 : 2
            guard let value else { problems.append("\(name) needs a value"); continue }
            switch name {
            case "-OTDatabasePath": databasePath = value
            case "-OTSeed":
                if let s = DebugSeed(rawValue: value) { seed = s } else { problems.append("unknown seed: \(value)") }
            case "-OTOpen":
                if let r = DebugRoute(value) { open = r } else { problems.append("unknown route: \(value)") }
            case "-OTSnapshot": snapshotPath = value
            case "-OTQuickAdd": quickAddText = value
            case "-OTWindowSize":
                if let s = DebugWindowSize(value) { windowSize = s } else { problems.append("bad window size: \(value)") }
            case "-OTInterfaceSize":
                if let s = InterfaceSize(rawValue: value) { interfaceSize = s } else { problems.append("unknown interface size: \(value)") }
            case "-OTHiddenWindows":
                if value == "yes" { hiddenWindows = true } else if value != "no" { problems.append("-OTHiddenWindows takes yes or no") }
            case "-OTTime":
                if let t = Self.timeOfDay(value) { timeOfDay = t } else { problems.append("-OTTime takes HH:MM, not \(value)") }
            case "-OTAppearance":
                if let a = DebugAppearance(rawValue: value) { appearance = a } else { problems.append("unknown appearance: \(value)") }
            default: problems.append("unknown option: \(name)")
            }
        }
    }

    /// "10:30" → 630; nil unless it's a time of day.
    static func timeOfDay(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    public static var current: DebugLaunch { DebugLaunch(arguments: ProcessInfo.processInfo.arguments) }

    public var databaseURL: URL? { databasePath.map(Self.resolve) }
    public var snapshotURL: URL? { snapshotPath.map(Self.resolve) }

    /// An absolute path as it is; a relative one inside the app's temporary
    /// directory.
    public static func resolve(_ path: String) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: path)
    }
}

/// `-OTWindowSize 760x460`.
public struct DebugWindowSize: Sendable, Hashable {
    public var width: Double
    public var height: Double

    public init?(_ text: String) {
        let parts = text.split(separator: "x")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0 else { return nil }
        width = w
        height = h
    }
}

public enum DebugAppearance: String, Sendable, Hashable, CaseIterable {
    case light, dark
}

public enum DebugSeed: String, Sendable, Hashable, CaseIterable {
    case demo
}

public enum DebugRoute: Sendable, Hashable {
    case home
    case smart(String)
    case list(String)
    case tag(String)
    case filter(String)
    case task(String)
    case calendar(String?)
    case calendarDemo(String?)
    case timeline
    /// The timeline component on demo data (`TimelineDemo.Scene`).
    case timelineDemo(String)
    /// `timeline:list:work`, `timeline:smart:today` …: that view as a timeline.
    case timelineView(String)
    /// The Settings window, on a tab (nil: the first).
    case settings(SettingsTab?)
    case schedule(String)
    case batch(String)
    case system(String)
    case search(String?)
    case filterEditor(String)
    /// `work`, `new:symbol` …: the list editor on a list (or a new one).
    case listEditor(String)
    case board(String)
    /// `habits`, `focus:stats` …: an efficiency module (the whole text).
    case efficiency(String)
    case prefs(String)
    case account(String)
    case selftest(String)

    /// The Settings window's tab a `settings:<tab>` route asks for.
    public var settingsTab: SettingsTab? {
        if case .settings(let tab) = self { tab } else { nil }
    }

    public init?(_ text: String) {
        let kind: Substring, arg: String?
        if let colon = text.firstIndex(of: ":") {
            kind = text[..<colon]
            arg = String(text[text.index(after: colon)...])
        } else {
            kind = Substring(text)
            arg = nil
        }
        switch (kind, arg) {
        case ("home", nil): self = .home
        case ("smart", let a?) where !a.isEmpty: self = .smart(a)
        case ("list", let a?) where !a.isEmpty: self = .list(a)
        case ("tag", let a?) where !a.isEmpty: self = .tag(a)
        case ("filter", let a?) where !a.isEmpty: self = .filter(a)
        case ("task", let a?) where !a.isEmpty: self = .task(a)
        case ("calendar", nil): self = .calendar(nil)
        case ("calendar", let a?) where !a.isEmpty: self = .calendar(a)
        case ("calendar-demo", nil): self = .calendarDemo(nil)
        case ("calendar-demo", let a?) where CalendarDemoState(rawValue: a) != nil: self = .calendarDemo(a)
        case ("timeline", nil): self = .timeline
        case ("timeline", let a?) where TimelineDemo.Scene(rawValue: a) != nil: self = .timelineDemo(a)
        case ("timeline", let a?) where DebugRoute(a).flatMap(TimelineDebugPresenter.view(of:)) != nil:
            self = .timelineView(a)
        case ("settings", nil): self = .settings(nil)
        case ("settings", let a?) where SettingsTab(rawValue: a) != nil: self = .settings(SettingsTab(rawValue: a))
        case ("schedule", let a?) where !a.isEmpty: self = .schedule(a)
        case ("batch", let a?) where !a.isEmpty: self = .batch(a)
        case ("system", let a?) where !a.isEmpty: self = .system(a)
        case ("search", nil): self = .search(nil)
        case ("search", let a?) where !a.isEmpty: self = .search(a)
        case ("filter-editor", let a?) where !a.isEmpty: self = .filterEditor(a)
        case ("list-editor", let a?) where !a.isEmpty: self = .listEditor(a)
        case ("board", let a?) where !a.isEmpty: self = .board(a)
        case ("habits", _), ("focus", _), ("countdowns", _), ("matrix", _): self = .efficiency(text)
        case ("prefs", let a?) where !a.isEmpty: self = .prefs(a)
        case ("account", let a?) where !a.isEmpty: self = .account(a)
        case ("selftest", let a?) where !a.isEmpty: self = .selftest(a)
        default: return nil
        }
    }

    /// The route as written on the command line.
    public var text: String {
        switch self {
        case .home: "home"
        case .smart(let k): "smart:\(k)"
        case .list(let id): "list:\(id)"
        case .tag(let t): "tag:\(t)"
        case .filter(let id): "filter:\(id)"
        case .task(let id): "task:\(id)"
        case .calendar(let mode): mode.map { "calendar:\($0)" } ?? "calendar"
        case .calendarDemo(let state): state.map { "calendar-demo:\($0)" } ?? "calendar-demo"
        case .timeline: "timeline"
        case .timelineDemo(let s): "timeline:\(s)"
        case .timelineView(let s): "timeline:\(s)"
        case .settings(let tab): tab.map { "settings:\($0.rawValue)" } ?? "settings"
        case .schedule(let s): "schedule:\(s)"
        case .batch(let s): "batch:\(s)"
        case .system(let s): "system:\(s)"
        case .search(let q): q.map { "search:\($0)" } ?? "search"
        case .filterEditor(let s): "filter-editor:\(s)"
        case .listEditor(let s): "list-editor:\(s)"
        case .board(let s): "board:\(s)"
        case .efficiency(let text): text
        case .prefs(let s): "prefs:\(s)"
        case .account(let s): "account:\(s)"
        case .selftest(let s): "selftest:\(s)"
        }
    }
}
