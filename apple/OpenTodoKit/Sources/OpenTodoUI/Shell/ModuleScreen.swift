// What each module's tab shows (iOS, iPadOS). Every module owns its whole
// tab: on iPad its own `NavigationSplitView` or `NavigationStack`, on
// iPhone its own `NavigationStack`. The Mac window lays the same modules
// out beside one sidebar (Shell/MacShell.swift). A new module adds a case
// in both.

import OpenTodoDomain
import SwiftUI

struct ModuleScreen: View {
    var module: AppModule

    var body: some View {
        switch module {
        case .tasks: TasksScreen()
        case .calendar: CalendarScreen()
        case .matrix, .focus, .habits, .countdowns: EfficiencyScreen(module: module)
        }
    }
}
