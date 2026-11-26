// Colours and symbols shared by every screen. Everything else (text,
// backgrounds, separators) uses the system's semantic colours, so dark
// mode and the accessibility settings work without anything here.

import OpenTodoDomain
import SwiftUI

public enum Palette {
    /// The app's accent, #14A38B; the same as the AccentColor asset.
    public static let accent = Color(red: 0x14 / 255, green: 0xA3 / 255, blue: 0x8B / 255)

    /// Priority colours, as `app/lib/ui/theme.dart`; no priority is the
    /// system's secondary grey.
    public static func priority(_ p: Priority) -> Color {
        switch p {
        case .high: Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255)
        case .medium: Color(red: 0xF2 / 255, green: 0xA5 / 255, blue: 0x16 / 255)
        case .low: Color(red: 0x3E / 255, green: 0x8B / 255, blue: 0xFF / 255)
        case .none: Color.secondary
        }
    }

    /// Overdue dates and the 已过期 header.
    public static let overdue = Color.red

    /// A list's own colour (ARGB, Flutter's `Color.value`), or the accent.
    public static func list(_ argb: Int?) -> Color {
        guard let argb else { return accent }
        return Color(red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
                     blue: Double(argb & 0xFF) / 255, opacity: Double((argb >> 24) & 0xFF) / 255)
    }
}

extension SmartKind {
    public var title: String {
        switch self {
        case .today: "今天"
        case .tomorrow: "明天"
        case .next7: "最近7天"
        case .inbox: "收集箱"
        case .completed: "已完成"
        case .trash: "垃圾桶"
        }
    }

    public var symbol: String {
        switch self {
        case .today: "sun.max"
        case .tomorrow: "sunrise"
        case .next7: "calendar.badge.clock"
        case .inbox: "tray"
        case .completed: "checkmark.circle"
        case .trash: "trash"
        }
    }

    public var tint: Color {
        switch self {
        case .today: .orange
        case .tomorrow: .pink
        case .next7: .purple
        case .inbox: .blue
        case .completed: .green
        case .trash: .gray
        }
    }
}

/// Symbols for the other kinds of view.
public enum ViewSymbol {
    public static let list = "list.bullet"
    public static let filter = "line.3.horizontal.decrease"
    public static let tag = "number"
}
