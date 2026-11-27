// The app's modules (任务, 日历, 四象限, 专注, 习惯, 倒数日): the top level of
// the app. On macOS the window has one sidebar for all of them
// (Shell/MacShell.swift): the tasks module is its views (今天, the lists …)
// and every other module is a row among them, under the smart lists; the
// 显示 menu has them too (⌘1, ⌘2 …). On iOS and iPadOS they are the tabs.
//
// To add a module: add a case here (its order is the order everywhere),
// give it a title, a symbol and a tint, and return its screen from
// `ModuleScreen` (Shell/ModuleScreen.swift, iOS) and `MacShell`'s detail.

import OpenTodoDomain
import SwiftUI

public enum AppModule: String, Sendable, Hashable, CaseIterable, Identifiable {
    case tasks
    case calendar
    // The efficiency modules (Efficiency/App/EfficiencyScreen.swift); on a
    // phone they share one tab.
    case matrix
    case focus
    case habits
    case countdowns

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tasks: "任务"
        case .calendar: "日历"
        case .matrix: "四象限"
        case .focus: "专注"
        case .habits: "习惯"
        case .countdowns: "倒数日"
        }
    }

    /// SF Symbol, outline; tab bars fill it themselves when selected.
    public var symbol: String {
        switch self {
        case .tasks: "checklist"
        case .calendar: "calendar"
        case .matrix: "square.grid.2x2"
        case .focus: "timer"
        case .habits: "leaf"
        case .countdowns: "hourglass"
        }
    }

    /// The colour of its icon in the Mac sidebar, beside the smart lists'
    /// (orange, pink, purple, blue).
    public var tint: Color {
        switch self {
        case .tasks: .accentColor
        case .calendar: .red
        case .matrix: .indigo
        case .focus: .orange
        case .habits: .green
        case .countdowns: .teal
        }
    }

    /// The modules that are rows of the Mac sidebar: all but 任务, which is
    /// the sidebar's views themselves.
    public static var sidebarModules: [AppModule] { allCases.filter { $0 != .tasks } }

    /// ⌘1, ⌘2 … in the order of the cases.
    public var shortcut: KeyEquivalent {
        let n = AppModule.allCases.firstIndex(of: self)! + 1
        return KeyEquivalent(Character(String(n)))
    }
}

/// A row of the Mac sidebar that can be selected: a view of the tasks
/// module, or another module.
public enum SidebarItem: Sendable, Hashable {
    case view(ViewRef)
    case module(AppModule)
}
