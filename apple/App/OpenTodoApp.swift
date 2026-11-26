import OpenTodoData
import OpenTodoUI
import SwiftUI

@main
struct OpenTodoApp: App {
    #if DEBUG
    private let debug: DebugLaunch? = DebugLaunch.current
    #else
    private let debug: DebugLaunch? = nil
    #endif
    /// Made once: every window and the Settings window share it.
    @State private var services: AppServices

    init() {
        let services = AppModel.launchServices(debug)
        _services = State(initialValue: services)
        // Outside writes, widgets and Spotlight, for the whole process.
        SystemSync.shared.start(database: services.database)
        #if os(macOS)
        // The global quick-add shortcut, and the model the menu bar window
        // and the quick-add panel share.
        SystemServices.shared.start(services: services, debug: debug)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(services: services, debug: debug)
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            AppCommands()
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView(services: services, tab: debug?.open?.settingsTab)
                // -OTAppearance for this window too (screenshots).
                .preferredColorScheme(debug?.appearance.map { $0 == .dark ? .dark : .light })
        }
        MenuBarScene()
        #endif
    }
}
