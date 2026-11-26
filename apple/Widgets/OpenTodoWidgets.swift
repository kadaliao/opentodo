// The widget extension: 今天 (the day's tasks, with 完成 buttons), 快速添加,
// 倒数日 and 习惯. Each reads the database the app shares through its App
// Group, read-only (`WidgetStore`); what to show and when to redraw is
// worked out in `OpenTodoSystem` (`todayWidget`, `widgetRefreshTimes`, …),
// which has the tests. Taps open the app through `opentodo://` links.

import OpenTodoSystem
import SwiftUI
import WidgetKit

@main
struct OpenTodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayTasksWidget()
        QuickAddWidget()
        CountdownWidget()
        HabitsTodayWidget()
    }
}

// MARK: - Shared pieces

enum WidgetLook {
    static let accent = Color(red: 0x14 / 255, green: 0xA3 / 255, blue: 0x8B / 255)

    /// Priority colours, as the app's `Palette`.
    static func priority(_ p: Priority) -> Color {
        switch p {
        case .high: Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255)
        case .medium: Color(red: 0xF2 / 255, green: 0xA5 / 255, blue: 0x16 / 255)
        case .low: Color(red: 0x3E / 255, green: 0x8B / 255, blue: 0xFF / 255)
        case .none: Color.secondary
        }
    }

    /// A stored ARGB colour, or the accent.
    static func color(_ argb: Int?) -> Color {
        guard let argb else { return accent }
        return Color(red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
                     blue: Double(argb & 0xFF) / 255)
    }

    /// This build's link scheme (the debug build has its own).
    static var scheme: String { AppLink.scheme() }

    static func url(_ link: AppLink) -> URL { link.url(scheme: scheme) }

    /// 11月26日 周四
    static func dayTitle(_ d: Day) -> String { "\(d.month)月\(d.day)日 \(weekdayName(d))" }
}

extension View {
    /// The system's widget background.
    func widgetBackground() -> some View {
        containerBackground(for: .widget) { Color("WidgetBackground") }
    }
}

// MARK: - 快速添加

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "quickadd", provider: StaticProvider()) { _ in
            QuickAddWidgetView()
        }
        .configurationDisplayName("快速添加")
        .description("点一下就添加任务。")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .accessoryCircular])
        #else
        .supportedFamilies([.systemSmall])
        #endif
    }
}

struct StaticProvider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }

    func placeholder(in context: Context) -> Entry { Entry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (WidgetKit.Timeline<Entry>) -> Void) {
        completion(WidgetKit.Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

struct QuickAddWidgetView: View {
    @Environment(\.widgetFamily) private var family

    private var isAccessory: Bool {
        #if os(iOS)
        family == .accessoryCircular
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if isAccessory {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "plus").font(.title2.weight(.semibold))
                }
                .accessibilityLabel("添加任务")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(WidgetLook.accent)
                    Spacer(minLength: 0)
                    Text("添加任务").font(.headline)
                    Text("明天下午3点开会 #工作")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .widgetURL(WidgetLook.url(.quickAdd))
        .widgetBackground()
    }
}
