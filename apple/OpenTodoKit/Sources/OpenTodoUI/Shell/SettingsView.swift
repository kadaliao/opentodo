// 设置 as the app shows it: on macOS the Settings window (⌘,), on iOS a
// sheet from the tasks tab's gear. Both are data's `OpenTodoSettingsView`
// on the app's services; this only wraps it so the App shell needn't know
// the services' parts.

import OpenTodoData
import OpenTodoDomain
import SwiftUI

/// macOS: the Settings scene's content.
public struct SettingsView: View {
    let services: AppServices
    let tab: SettingsTab

    /// `tab`: the one to open on (the `settings:<tab>` debug route).
    public init(services: AppServices, tab: SettingsTab? = nil) {
        self.services = services
        self.tab = tab ?? .general
    }

    public var body: some View {
        OpenTodoSettingsView(settings: services.settings, sync: services.sync, reminders: services.reminders, tab: tab)
            .interfaceScaleRoot()
    }
}

/// iOS: the settings sheet, with a 完成 button.
struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            OpenTodoSettingsView(settings: model.settings, sync: model.services?.sync, reminders: model.services?.reminders)
                .navigationTitle("设置")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成", systemImage: "checkmark") { dismiss() }
                    }
                }
        }
    }
}
