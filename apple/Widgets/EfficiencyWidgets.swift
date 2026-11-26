// 倒数日 (one countdown, picked in the widget's settings, as a big number)
// and 习惯 (today's habits and how far each is). Both redraw at midnight;
// the app reloads them when their data changes.

import AppIntents
import OpenTodoSystem
import SwiftUI
import WidgetKit

/// The next midnight, when the counts move on.
private func nextMidnight() -> Date { LocalDateTime(Day.today() + 1).date() }

// MARK: - 倒数日

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "countdown", intent: SelectCountdownIntent.self, provider: CountdownProvider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("倒数日")
        .description("离重要的日子还有几天。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CountdownEntry: TimelineEntry {
    let date: Date
    let countdown: WidgetCountdown?
}

struct CountdownProvider: AppIntentTimelineProvider {
    static let sample = WidgetCountdown(id: "s", title: "春节", emoji: "🧧", color: 0xFFE5484D, days: 72, past: false,
                                        dateText: "2027年2月6日 周六")

    func placeholder(in context: Context) -> CountdownEntry { CountdownEntry(date: .now, countdown: Self.sample) }

    func snapshot(for configuration: SelectCountdownIntent, in context: Context) async -> CountdownEntry {
        let e = await entry(configuration)
        return context.isPreview && e.countdown == nil ? placeholder(in: context) : e
    }

    func timeline(for configuration: SelectCountdownIntent, in context: Context) async -> WidgetKit.Timeline<CountdownEntry> {
        WidgetKit.Timeline(entries: [await entry(configuration)], policy: .after(nextMidnight()))
    }

    private func entry(_ configuration: SelectCountdownIntent) async -> CountdownEntry {
        let cs = await WidgetStore.countdowns(WidgetStore.open())
        return CountdownEntry(date: .now, countdown: widgetCountdown(cs, picked: configuration.countdown?.id, today: Day.today()))
    }
}

struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownEntry

    var body: some View {
        Group {
            if let c = entry.countdown {
                if family == .systemSmall { small(c) } else { medium(c) }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "hourglass").font(.title2).foregroundStyle(WidgetLook.accent)
                    Text("还没有倒数日").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(WidgetLook.url(.countdowns))
        .containerBackground(for: .widget) {
            Rectangle().fill(entry.countdown.map { WidgetLook.color($0.color).gradient } ?? Color("WidgetBackground").gradient)
        }
    }

    private func title(_ c: WidgetCountdown) -> some View {
        Text("\(c.emoji.map { "\($0) " } ?? "")\(c.title)")
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
    }

    private func number(_ c: WidgetCountdown, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(c.days)")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text("天").font(.subheadline.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(c.lead) \(c.days) 天")
    }

    private func small(_ c: WidgetCountdown) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title(c)
            Spacer(minLength: 0)
            Text(c.lead).font(.caption).opacity(0.85)
            number(c, size: 46)
            Text(c.dateText).font(.caption2).opacity(0.85).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
    }

    private func medium(_ c: WidgetCountdown) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                title(c).font(.headline)
                Spacer(minLength: 0)
                Text(c.dateText).font(.caption).opacity(0.85)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(c.lead).font(.caption).opacity(0.85)
                number(c, size: 60)
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: - 习惯

struct HabitsTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "habits", provider: HabitsProvider()) { entry in
            HabitsWidgetView(entry: entry)
        }
        .configurationDisplayName("习惯")
        .description("今天的习惯打卡了几个。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct HabitsEntry: TimelineEntry {
    let date: Date
    let content: HabitsWidget
}

struct HabitsProvider: TimelineProvider {
    static let sample = HabitsWidget(habits: [
        WidgetHabit(id: "1", name: "喝水", emoji: "💧", color: 0xFF3E8BFF, progress: 0.5, amountText: "4/8杯"),
        WidgetHabit(id: "2", name: "早起", emoji: "🌅", color: 0xFFF2A516, progress: 1, done: true),
        WidgetHabit(id: "3", name: "读书", emoji: "📚", color: 0xFF8E6CEF),
    ], done: 1, due: 3)

    func placeholder(in context: Context) -> HabitsEntry { HabitsEntry(date: .now, content: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (HabitsEntry) -> Void) {
        let preview = context.isPreview
        Task {
            let e = await Self.entry()
            completion(preview && e.content.due == 0 ? HabitsEntry(date: .now, content: Self.sample) : e)
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (WidgetKit.Timeline<HabitsEntry>) -> Void) {
        Task { completion(WidgetKit.Timeline(entries: [await Self.entry()], policy: .after(nextMidnight()))) }
    }

    static func entry() async -> HabitsEntry {
        let (habits, checkins) = await WidgetStore.habits(WidgetStore.open())
        return HabitsEntry(date: .now, content: habitsWidget(habits, checkins: checkins, today: Day.today()))
    }
}

struct HabitsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HabitsEntry

    private var content: HabitsWidget { entry.content }

    var body: some View {
        Group {
            if content.habits.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "leaf").font(.title2).foregroundStyle(WidgetLook.accent)
                    Text("今天没有要打卡的习惯").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if family == .systemSmall {
                small
            } else {
                list
            }
        }
        .widgetURL(WidgetLook.url(.habits))
        .widgetBackground()
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("习惯").font(.headline).foregroundStyle(WidgetLook.accent)
            Spacer(minLength: 0)
            ZStack {
                Ring(progress: content.due == 0 ? 0 : Double(content.done) / Double(content.due), color: WidgetLook.accent,
                     width: 9)
                VStack(spacing: 0) {
                    Text("\(content.done)/\(content.due)").font(.title2.weight(.bold)).monospacedDigit()
                    Text("已打卡").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 86, height: 86)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }

    private var list: some View {
        let limit = family == .systemMedium ? 4 : 9
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("习惯").font(.title3.weight(.semibold)).foregroundStyle(WidgetLook.accent)
                Spacer()
                Text("\(content.done)/\(content.due)").font(.headline).monospacedDigit()
            }
            if family == .systemMedium {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(content.habits.prefix(limit)) { HabitLine(habit: $0) }
                }
            } else {
                ForEach(content.habits.prefix(limit)) { HabitLine(habit: $0) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct HabitLine: View {
    let habit: WidgetHabit

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Ring(progress: habit.progress, color: WidgetLook.color(habit.color), width: 3.5)
                if habit.done {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(WidgetLook.color(habit.color))
                } else {
                    Text(habit.emoji ?? String(habit.name.prefix(1))).font(.caption)
                }
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(habit.name).font(.subheadline).lineLimit(1)
                if let a = habit.amountText {
                    Text(a).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(habit.done ? "已完成" : "未完成")
    }
}

private struct Ring: View {
    let progress: Double
    let color: Color
    let width: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
