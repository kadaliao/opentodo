// The root of a window: makes the window's `AppModel` (opening the
// database; the debug launch options in Debug builds) and lays out the
// modules — on macOS one module at a time with the module bar in its
// sidebar, on iOS and iPadOS a tab per module plus 搜索. Dialogs and the
// undo banner are attached here, once for the whole window.

import OpenTodoData
import OpenTodoDomain
import SwiftUI

public struct RootView: View {
    private let debug: DebugLaunch?
    @State private var model: AppModel

    /// `services`: the app's, made once by the App (`AppModel
    /// .launchServices`); nil makes its own (previews). `debug` is
    /// `DebugLaunch.current` in Debug builds, nil in Release.
    public init(services: AppServices? = nil, debug: DebugLaunch? = nil) {
        self.debug = debug
        _model = State(initialValue: AppModel.forLaunch(debug, services: services))
        if let problems = debug?.problems, !problems.isEmpty {
            print("OpenTodo: ignored launch options: \(problems.joined(separator: "; "))")
        }
    }

    public var body: some View {
        root
            // Replaces the content for its routes, so it goes inside the
            // modifiers that set the debug appearance.
            .modifier(SettingsDebugPresenter(route: debug?.open, databaseURL: debug?.databaseURL))
            .modifier(WindowRestoration(enabled: debug?.open == nil))
            .modifier(DialogHost())
            .modifier(SearchHost())
            .modifier(NoticeBanner())
            .modifier(UndoManagerHook())
            .modifier(ServicesHook())
            .task { await model.start() }
            .preferredColorScheme(debug?.appearance.map { $0 == .dark ? .dark : .light })
            .modifier(ScheduleDebugPresenter(route: debug?.open))
            .modifier(BatchDebugPresenter(route: debug?.open))
            .modifier(SearchDebugScreens(route: debug?.open))
            .modifier(BoardDebugPresenter(route: debug?.open))
            .modifier(TimelineDebugPresenter(route: debug?.open))
            .modifier(EfficiencyDebugPresenter(route: debug?.open))
            .modifier(SystemIntegration(route: debug?.open))
            .modifier(SnapshotOnAppear(url: debug?.snapshotURL))
            #if os(macOS)
            .focusedSceneValue(\.appModel, model)
            .frame(minWidth: 760, minHeight: 460)
            .background { if let size = debug?.windowSize { DebugWindowSizer(size: size) } }
            #endif
            // Outermost, so every modifier above can read it.
            .environment(model)
    }

    /// The app, or one feature's demo screen when a debug route asks for it.
    @ViewBuilder private var root: some View {
        if case .calendarDemo(let state)? = debug?.open {
            CalendarDemoHost(state: state.flatMap(CalendarDemoState.init(rawValue:)) ?? .month)
        } else if case .timelineDemo(let scene)? = debug?.open, let scene = TimelineDemo.Scene(rawValue: scene) {
            TimelineDemo(scene: scene)
        } else {
            Shell()
        }
    }
}

/// Tells the services when the app comes to the front or goes to the
/// background, and opens what a notification asks for.
private struct ServicesHook: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .onChange(of: phase) { _, phase in
                switch phase {
                case .active: model.services?.appDidBecomeActive()
                case .background: model.services?.appDidEnterBackground()
                default: break
                }
            }
            .onChange(of: model.services?.reminders.openRequest, initial: true) { _, request in
                guard let request else { return }
                model.services?.reminders.openRequest = nil
                model.handle(request)
            }
    }
}

/// Hands the window's undo manager to `Notices`, for ⌘Z.
private struct UndoManagerHook: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        content.onAppear { model.notices.undoManager = undoManager }
            .onChange(of: undoManager) { model.notices.undoManager = undoManager }
    }
}

private struct Shell: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #else
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        #if os(macOS)
        ModuleScreen(module: model.module)
            .onChange(of: model.present.settings, initial: true) { _, want in
                if want {
                    model.present.settings = false
                    openSettings()
                }
            }
        #else
        TabView(selection: Binding(
            get: { model.search.isPresented ? RootTab.search : RootTab.module(model.module) },
            set: { tab in
                switch tab {
                case .module(let m): model.search.isPresented = false; model.switchTo(m)
                case .search: model.search.isPresented = true
                }
            })) {
            // On a phone the efficiency modules share one tab (EfficiencyScreen.swift).
            let compact = sizeClass == .compact
            ForEach(AppModule.tabs(compact: compact, current: model.module, last: model.efficiency.lastModule)) { m in
                Tab(m.tabTitle(compact: compact), systemImage: m.tabSymbol(compact: compact), value: RootTab.module(m)) {
                    ModuleScreen(module: m)
                }
            }
            Tab(value: RootTab.search, role: .search) {
                SearchScreen()
            }
        }
        .onChange(of: sizeClass, initial: true) { _, c in
            model.setWidth(c == .compact ? .compact : .regular)
        }
        .onChange(of: model.module) { model.search.isPresented = false }
        #endif
    }
}

#if os(iOS)
private enum RootTab: Hashable {
    case module(AppModule)
    case search
}
#endif

#Preview {
    RootView(debug: DebugLaunch(databasePath: "preview/opentodo.sqlite", seed: .demo))
}
