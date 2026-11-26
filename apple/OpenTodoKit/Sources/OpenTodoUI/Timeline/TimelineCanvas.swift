// What the timeline draws behind its bars: the days along the top, days off
// tinted, and lines between days (between weeks and months when they're
// narrow). Each is a `Canvas` over a band of the strip a little wider than
// the screen, starting at content x `minX`.

import OpenTodoDomain
import SwiftUI

/// Days off: public holidays, else the weekend (a weekend day worked, 班,
/// isn't one).
func isDayOff(_ d: Day) -> Bool { holidayOn(d)?.off ?? (d.weekday >= 6) }

struct TimelineGrid: View {
    let geometry: TimelineGeometry
    let minX: Double

    var body: some View {
        let g = geometry
        let minX = minX
        Canvas { context, size in
            let first = g.day(atContentX: minX)
            let last = g.day(atContentX: minX + size.width)
            let tint = GraphicsContext.Shading.color(.primary.opacity(0.035))
            let thin = GraphicsContext.Shading.color(.primary.opacity(0.07))
            let bold = GraphicsContext.Shading.color(.primary.opacity(0.16))
            var d = first
            while d <= last {
                let x = g.contentX(d) - minX
                if g.scale != .month && isDayOff(d) {
                    context.fill(Path(CGRect(x: x, y: 0, width: g.dayWidth, height: size.height)), with: tint)
                }
                let line: GraphicsContext.Shading? = switch g.scale {
                case .day: d.day == 1 ? bold : thin
                case .week, .month: d.day == 1 ? bold : (d.weekday == 1 ? thin : nil)
                }
                if let line {
                    context.fill(Path(CGRect(x: x, y: 0, width: 1 / 1, height: size.height).insetBy(dx: 0.25, dy: 0)), with: line)
                }
                d += 1
            }
        }
    }
}

struct TimelineDayHeader: View {
    let geometry: TimelineGeometry
    let minX: Double
    let today: Day
    /// The days a dragged task would land on.
    let drop: TimelineDropDays?

    var body: some View {
        let g = geometry
        let minX = minX
        let today = today
        let drop = drop
        Canvas { context, size in
            let first = g.day(atContentX: minX)
            let last = g.day(atContentX: minX + size.width)
            if let drop {
                let r = CGRect(x: g.contentX(drop.start) - minX + 1, y: 3, width: Double(drop.days) * g.dayWidth - 2, height: size.height - 6)
                context.fill(Path(roundedRect: r, cornerRadius: 7, style: .continuous), with: .color(.accentColor.opacity(0.16)))
            }
            if g.scale == .month {
                // Each month's name where it starts (the one on screen at
                // the left edge stays there until the next pushes it out),
                // and every Monday's date.
                var month = first.startOfMonth
                let screenLeft = g.scrollX - minX
                while month <= last {
                    let next = month.addingMonths(1)
                    let left = max(g.contentX(month) - minX, screenLeft)
                    let room = g.contentX(next) - minX - left
                    if room > 24 {
                        let name = month.month == 1 ? "\(month.year)年1月" : "\(month.month)月"
                        let text = Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                        var c = context
                        c.clip(to: Path(CGRect(x: left, y: 0, width: room - 2, height: size.height)))
                        c.draw(text, at: CGPoint(x: left + 6, y: 6), anchor: .topLeading)
                    }
                    month = next
                }
                var d = first.startOfWeek
                while d <= last {
                    let x = g.contentX(d) - minX
                    context.draw(
                        Text("\(d.day)").font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary),
                        at: CGPoint(x: x + 2, y: 24), anchor: .topLeading
                    )
                    d += 7
                }
                if today >= first && today <= last {
                    let x = g.contentX(today) - minX + g.dayWidth / 2
                    context.fill(Path(ellipseIn: CGRect(x: x - 3, y: 37, width: 6, height: 6)), with: .color(.red))
                }
            } else {
                let wide = g.scale == .day
                var d = first
                while d <= last {
                    let x = g.contentX(d) - minX
                    let mid = x + g.dayWidth / 2
                    let isToday = d == today
                    let off = isDayOff(d)
                    let weekday = wide ? weekdayName(d) : String(weekdayName(d).dropFirst())
                    context.draw(
                        Text(weekday).font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isToday ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary)),
                        at: CGPoint(x: mid, y: 13)
                    )
                    let label = d.day == 1 ? "\(d.month)月" : "\(d.day)"
                    let weight: Font.Weight = isToday || d.day == 1 ? .semibold : .regular
                    if isToday {
                        let w = max(22, Double(label.count) * 8 + 10)
                        context.fill(
                            Path(roundedRect: CGRect(x: mid - w / 2, y: 20, width: w, height: 20), cornerRadius: 10),
                            with: .color(.red)
                        )
                        context.draw(Text(label).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.white),
                                     at: CGPoint(x: mid, y: 30))
                    } else {
                        let style: AnyShapeStyle = d.day == 1 ? AnyShapeStyle(Color.accentColor)
                            : off ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
                        context.draw(Text(label).font(.system(size: 13, weight: weight).monospacedDigit()).foregroundStyle(style),
                                     at: CGPoint(x: mid, y: 30))
                    }
                    d += 1
                }
            }
            context.fill(Path(CGRect(x: 0, y: size.height - 0.5, width: size.width, height: 0.5)), with: .color(.primary.opacity(0.15)))
        }
        .accessibilityElement()
        .accessibilityLabel(timelineMonthLabel(g.leftDay))
    }
}

/// The view's open tasks without a date (无日期), beside the timeline: drag
/// one onto a day to give it that date, or a task from the timeline here to
/// take its date away.
struct TimelineTray<TaskMenu: View>: View {
    let groups: [UndatedGroup]
    /// The lanes have headers: show which group each task is in.
    let titled: Bool
    /// A dragged task would lose its date here.
    let highlighted: Bool
    let dragged: Set<String>
    let isSelected: (String) -> Bool
    let onTap: (String) -> Void
    let onSetDone: (TodoTask, Bool) -> Void
    let onBegan: (TodoTask, CGPoint) -> Void
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void
    let onCancelled: () -> Void
    let onStill: (TodoTask, CGRect) -> Void
    let taskMenu: (TodoTask) -> TaskMenu

    var body: some View {
        let count = groups.reduce(0) { $0 + $1.tasks.count }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("无日期").font(.headline)
                Text("\(count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if count > 0 {
                    Text("拖到日期上").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)
            if count == 0 {
                Text("没有无日期的任务\n把时间线上的任务拖到这里，可以去掉日期")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                            if titled, let title = g.title {
                                Text(title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)
                            }
                            ForEach(g.tasks) { t in row(t) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary)
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
                    .strokeBorder(Color.accentColor, lineWidth: 1)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    private func row(_ t: TodoTask) -> some View {
        let selected = isSelected(t.id)
        return HStack(spacing: 8) {
            TimelineCheckbox(done: false, priority: t.priority, size: 15) { onSetDone(t, true) }
            Text(TimelineStyle.title(t))
                .font(.system(size: 13))
                .foregroundStyle(t.title.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.045))
        )
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .opacity(dragged.contains(t.id) ? 0.3 : 1)
        .contentShape(Rectangle())
        .onTapGesture { onTap(t.id) }
        .modifier(PressDrag(
            enabled: true,
            space: timelineSpace,
            onBegan: { p in onBegan(t, p) },
            onChanged: onChanged,
            onEnded: onEnded,
            onCancelled: onCancelled,
            onStill: { onStill(t, rowRect[t.id] ?? .zero) }
        ))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(timelineSpace)) } action: { rowRect[t.id] = $0 }
        #if os(macOS)
        .contextMenu { taskMenu(t) }
        #endif
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(TimelineStyle.title(t))，无日期")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @State private var rowRect: [String: CGRect] = [:]
}
