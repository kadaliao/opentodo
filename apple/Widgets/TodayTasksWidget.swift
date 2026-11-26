// 今天: the 今天 view's open tasks (overdue first), the priority colour on
// each circle, its time on the right. The circle is a 完成 button
// (`CompleteTaskIntent`, written here in the extension; the app syncs it
// later); a line opens the task (medium and large — a small widget opens
// 今天 as a whole). The timeline redraws when a task turns due and at
// midnight (`widgetRefreshTimes`).

import AppIntents
import OpenTodoSystem
import SwiftUI
import WidgetKit

struct TodayTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("今天")
        .description("今天要做的任务，点圆圈完成。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let content: TodayWidget
}

struct TodayProvider: TimelineProvider {
    static func limit(_ family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 4
        default: 10
        }
    }

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, content: Self.sample(limit: Self.limit(context.family)))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayEntry) -> Void) {
        let family = context.family, preview = context.isPreview
        Task {
            let entries = await Self.entries(limit: Self.limit(family))
            let first = entries.first ?? TodayEntry(date: .now, content: TodayWidget(today: Day.today()))
            completion(preview && first.content.total == 0 ? TodayEntry(date: .now, content: Self.sample(limit: Self.limit(family))) : first)
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (WidgetKit.Timeline<TodayEntry>) -> Void) {
        let family = context.family
        Task {
            completion(WidgetKit.Timeline(entries: await Self.entries(limit: Self.limit(family)), policy: .atEnd))
        }
    }

    /// Now, then every moment the list changes by itself.
    static func entries(limit: Int) async -> [TodayEntry] {
        let data = await WidgetStore.taskData(WidgetStore.open())
        let now = LocalDateTime.now()
        return ([now] + widgetRefreshTimes(data.tasks, now: now)).map { t in
            TodayEntry(date: t.date(), content: todayWidget(data.tasks, lists: data.lists, now: t, limit: limit))
        }
    }

    static func sample(limit: Int) -> TodayWidget {
        let tasks = [
            WidgetTask(id: "1", title: "评审设计稿的第二版", priority: .high, timeText: "昨天", overdue: true),
            WidgetTask(id: "2", title: "部门周会", priority: .medium, timeText: "上午10:00-11:00", repeats: true),
            WidgetTask(id: "3", title: "写第四季度工作总结", priority: .high, timeText: "下午3:00"),
            WidgetTask(id: "4", title: "超市：牛奶、鸡蛋、面包", timeText: "下午7:00"),
        ]
        return TodayWidget(tasks: Array(tasks.prefix(limit)), total: 6, overdue: 1, today: Day.today())
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var content: TodayWidget { entry.content }
    private var small: Bool { family == .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: small ? 6 : 8) {
            header
            if content.tasks.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(WidgetLook.accent)
                    Text("今天没有任务了").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: small ? 6 : 9) {
                    ForEach(content.tasks) { task in
                        TodayRow(task: task, small: small)
                    }
                }
                Spacer(minLength: 0)
                if content.more > 0 {
                    Text("还有 \(content.more) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLook.url(.today))
        .widgetBackground()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("今天")
                .font(small ? .headline : .title3.weight(.semibold))
                .foregroundStyle(WidgetLook.accent)
            if !small {
                Text(WidgetLook.dayTitle(content.today))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if content.total > 0 {
                Text("\(content.total)")
                    .font(small ? .headline : .title3.weight(.semibold))
                    .foregroundStyle(content.overdue > 0 ? Color.red : Color.primary)
                    .accessibilityLabel("\(content.total) 项")
            }
        }
    }
}

private struct TodayRow: View {
    let task: WidgetTask
    let small: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: CompleteTaskIntent(taskId: task.id)) {
                Image(systemName: "circle")
                    .font(.system(size: small ? 15 : 17, weight: .medium))
                    .foregroundStyle(WidgetLook.priority(task.priority))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("完成 \(task.title)")
            if small {
                label
            } else {
                Link(destination: WidgetLook.url(.task(task.id))) { label }
            }
        }
        .invalidatableContent()
    }

    private var label: some View {
        HStack(spacing: 6) {
            Text(task.title)
                .font(small ? .caption : .subheadline)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !small, let time = task.timeText {
                if task.repeats {
                    Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary)
                }
                Text(time)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(task.overdue ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
        }
    }
}
