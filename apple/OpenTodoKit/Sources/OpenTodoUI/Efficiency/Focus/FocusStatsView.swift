// 专注统计: today's and all-time totals, focus per day / week / month as a
// bar chart, where the time went (by task or by list), and one day's
// timeline.

import Charts
import OpenTodoDomain
import SwiftUI

struct FocusStatsView: View {
    var sessions: [FocusSession]
    var tasks: [TodoTask]
    var lists: [TaskList]
    var today: Day
    var timeZone: TimeZone

    @State private var bucket: FocusBucket = .day
    @State private var byList = false
    @State private var day: Day

    init(sessions: [FocusSession], tasks: [TodoTask], lists: [TaskList], today: Day, timeZone: TimeZone) {
        self.sessions = sessions
        self.tasks = tasks
        self.lists = lists
        self.today = today
        self.timeZone = timeZone
        _day = State(initialValue: today)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                overview
                bars
                distribution
                timeline
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Color.groupedBackground)
        .navigationTitle("专注统计")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Overview

    private var overview: some View {
        let t = focusSummary(sessions, on: today, in: timeZone)
        let all = focusSummary(sessions, in: timeZone)
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(title: "今日专注", value: durationText(t.seconds), unit: "", symbol: "clock.fill", tint: .accentColor)
                StatTile(title: "今日番茄", value: "\(t.pomodoros)", unit: "个", symbol: "timer", tint: .red)
            }
            GridRow {
                StatTile(title: "总专注", value: durationText(all.seconds), unit: "", symbol: "hourglass", tint: .indigo)
                StatTile(title: "总番茄", value: "\(all.pomodoros)", unit: "个", symbol: "flame.fill", tint: .orange)
            }
        }
    }

    // MARK: Bars

    private var bars: some View {
        let range = focusChartRange(bucket, today: today)
        let data = focusSeries(sessions, from: range.from, through: range.through, by: bucket, in: timeZone)
        let total = data.reduce(0) { $0 + $1.seconds }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("专注时长").font(.headline)
                Spacer()
                Picker("按", selection: $bucket) {
                    Text("日").tag(FocusBucket.day)
                    Text("周").tag(FocusBucket.week)
                    Text("月").tag(FocusBucket.month)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }
            Text("共\(durationText(total))，平均每\(bucket == .day ? "天" : bucket == .week ? "周" : "月")\(durationText(data.isEmpty ? 0 : total / data.count))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Chart(data, id: \.start) { bar in
                BarMark(
                    x: .value("日期", focusBarLabel(bar.start, bucket)),
                    y: .value("分钟", bar.seconds / 60)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine()
                    AxisValueLabel { if let m = v.as(Int.self) { Text(m >= 60 && m % 60 == 0 ? "\(m / 60)时" : "\(m)分") } }
                }
            }
            .frame(height: 200)
            .accessibilityLabel(Text("每\(bucket == .day ? "天" : bucket == .week ? "周" : "月")的专注时长"))
        }
        .panel()
    }

    // MARK: Distribution

    private var distribution: some View {
        let range = focusChartRange(bucket, today: today)
        let inRange = focusSessions(sessions, from: range.from, through: range.through, in: timeZone)
        let slices = byList
            ? focusSlices(focusByList(inRange, tasks: tasks)) { id in
                id.map { lid in lid == inboxListId ? "收集箱" : lists.first { $0.id == lid }?.name ?? "已删除的清单" } ?? "未关联任务"
            }
            : focusSlices(focusByTask(inRange)) { id in
                id.map { tid in tasks.first { $0.id == tid }?.title ?? "已删除的任务" } ?? "未关联任务"
            }
        let total = max(slices.reduce(0) { $0 + $1.seconds }, 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("专注分布").font(.headline)
                Spacer()
                Picker("按", selection: $byList) {
                    Text("任务").tag(false)
                    Text("清单").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
            }
            if slices.isEmpty {
                Text("这段时间还没有专注记录").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                HStack(alignment: .center, spacing: 20) {
                    Chart(slices) { s in
                        SectorMark(angle: .value("时长", s.seconds), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(by: .value("名称", s.name))
                            .cornerRadius(3)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(slices.enumerated()), id: \.element.id) { i, s in
                            HStack(spacing: 8) {
                                Circle().fill(sliceColor(i)).frame(width: 8, height: 8)
                                Text(s.name).lineLimit(1)
                                Spacer(minLength: 4)
                                Text("\(durationText(s.seconds)) · \(s.seconds * 100 / total)%")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .chartForegroundStyleScale(range: (0..<slices.count).map(sliceColor))
            }
        }
        .panel()
    }

    /// The colours the pie and its legend share (Charts' default order).
    private func sliceColor(_ i: Int) -> Color {
        [Color.blue, .green, .orange, .purple, .red, .teal, .yellow, .pink][i % 8]
    }

    // MARK: Timeline

    private var timeline: some View {
        let items = focusTimeline(sessions, on: day, in: timeZone)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("专注时间轴").font(.headline)
                Spacer()
                Button("前一天", systemImage: "chevron.left") { day -= 1 }
                Text(day == today ? "今天" : dayText(day, today: today))
                    .font(.subheadline)
                    .monospacedDigit()
                Button("后一天", systemImage: "chevron.right") { day += 1 }
                    .disabled(day >= today)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            FocusDayBar(items: items)
            if items.isEmpty {
                Text("这天没有专注").font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(items, id: \.session.id) { item in
                        FocusSessionRow(session: item.session, taskTitle: tasks.first { $0.id == item.session.taskId }?.title, timeZone: timeZone)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
        .panel()
    }
}

/// The 24 hours of a day as a bar, each session a block on it.
struct FocusDayBar: View {
    var items: [FocusTimelineItem]

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12))
                    ForEach(items, id: \.session.id) { item in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.session.kind == .stopwatch ? Color.teal : Color.accentColor)
                            .frame(width: max(w * CGFloat(item.endMinute - item.startMinute) / 1440, 2))
                            .offset(x: w * CGFloat(item.startMinute) / 1440)
                    }
                }
            }
            .frame(height: 24)
            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                    Text("\(h)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    if h < 24 { Spacer() }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("这天专注了\(items.count)次"))
    }
}
