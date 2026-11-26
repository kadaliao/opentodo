// The app's modules (任务, 日历, and later 专注, 习惯 …): the top level of
// the app. On macOS they are the icon bar at the top of the sidebar and the
// 显示 menu (⌘1, ⌘2 …); on iOS and iPadOS they are the tabs.
//
// To add a module: add a case here (its order is the order everywhere),
// give it a title, a symbol and a shortcut, and return its screen from
// `ModuleScreen` (Shell/ModuleScreen.swift). Nothing else needs to know.

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

    /// ⌘1, ⌘2 … in the order of the cases.
    public var shortcut: KeyEquivalent {
        let n = AppModule.allCases.firstIndex(of: self)! + 1
        return KeyEquivalent(Character(String(n)))
    }
}
