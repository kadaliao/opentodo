// What each module shows. Every module owns its whole window area: on
// macOS and iPad its own `NavigationSplitView` (whose sidebar carries the
// module bar on macOS via `.moduleBar()`), on iPhone its own
// `NavigationStack`. A new module adds a case here.

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
