// 倒数纪念日: the module's root. A grid of cards, pinned first, then the
// nearest; each shows how many days to go or gone by, in the format picked
// for it (tap the number to switch). Detail and editor open from here.
//
// A self-contained component: it gets the countdowns and today, and hands
// every change back as a whole record (`onSave`; deleting sets
// `deletedAt`). The format of each card is the caller's to keep if it
// wants (`formats` / `onFormatChange`); otherwise it lasts while the view
// does.
//
//     CountdownsRootView(countdowns: countdowns, today: today, onSave: repo.save)

import OpenTodoDomain
import SwiftUI

public struct CountdownsRootView: View {
    @Environment(\.uiScale) private var s
    public var countdowns: [Countdown]
    public var today: Day
    public var onSave: (Countdown) -> Void
    public var formats: [String: CountdownFormat]
    public var onFormatChange: (String, CountdownFormat) -> Void
    var newId: () -> String
    var clock: () -> Int

    @State private var path: [String]
    @State private var editor: CountdownEditorTarget?
    @State private var localFormats: [String: CountdownFormat] = [:]

    public init(
        countdowns: [Countdown],
        today: Day,
        onSave: @escaping (Countdown) -> Void,
        formats: [String: CountdownFormat] = [:],
        onFormatChange: @escaping (String, CountdownFormat) -> Void = { _, _ in },
        newId: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.init(countdowns: countdowns, today: today, onSave: onSave, formats: formats, onFormatChange: onFormatChange,
                  newId: newId, clock: millisNow, start: .cards)
    }

    enum Start: Hashable {
        case cards
        case detail(String)
        case editor(String?)
    }

    init(
        countdowns: [Countdown], today: Day, onSave: @escaping (Countdown) -> Void,
        formats: [String: CountdownFormat], onFormatChange: @escaping (String, CountdownFormat) -> Void,
        newId: @escaping () -> String, clock: @escaping () -> Int, start: Start
    ) {
        self.countdowns = countdowns
        self.today = today
        self.onSave = onSave
        self.formats = formats
        self.onFormatChange = onFormatChange
        self.newId = newId
        self.clock = clock
        if case .detail(let id) = start { _path = State(initialValue: [id]) } else { _path = State(initialValue: []) }
        if case .editor(let id) = start {
            _editor = State(initialValue: CountdownEditorTarget(countdownId: id, kind: .countdown))
        }
    }

    private func format(_ id: String) -> CountdownFormat { localFormats[id] ?? formats[id] ?? .days }

    public var body: some View {
        let sorted = sortCountdowns(countdowns, today: today)
        NavigationStack(path: $path) {
            ScrollView {
                if sorted.isEmpty {
                    ContentUnavailableView {
                        Label("还没有倒数日", systemImage: "calendar.badge.clock")
                    } description: {
                        Text("记下生日、纪念日，或者一个盼着的日子。")
                    } actions: {
                        addMenu.menuStyle(.button).buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 60 * s)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160 * s, maximum: 280 * s), spacing: 14 * s)], spacing: 14 * s) {
                    ForEach(sorted) { c in
                        NavigationLink(value: c.id) {
                            CountdownCard(countdown: c, today: today, format: format(c.id)) {
                                let f = nextFormat(format(c.id))
                                localFormats[c.id] = f
                                onFormatChange(c.id, f)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(c) }
                    }
                }
                .padding()
            }
            .background(Color.groupedBackground)
            .navigationTitle("倒数纪念日")
            .efficiencyTitleMenu()
            .toolbar {
                ToolbarItem(placement: .primaryAction) { addMenu }
            }
            .navigationDestination(for: String.self) { id in
                if let c = countdowns.first(where: { $0.id == id && $0.deletedAt == nil }) {
                    CountdownDetailView(
                        countdown: c, today: today, format: format(id),
                        onEdit: { editor = CountdownEditorTarget(countdownId: id, kind: c.kind) },
                        onPin: { onSave(togglingPin(c, now: clock())) },
                        onDelete: {
                            onSave(deletedCountdown(c, now: clock()))
                            path.removeAll()
                        }
                    )
                } else {
                    ContentUnavailableView("已删除", systemImage: "calendar")
                }
            }
        }
        .sheet(item: $editor) { target in
            CountdownEditorView(
                countdown: target.countdownId.flatMap { id in countdowns.first { $0.id == id } },
                kind: target.kind, today: today
            ) { draft, base in
                onSave(draft.countdown(base: base, newId: newId(), now: clock()))
            }
        }
    }

    private var addMenu: some View {
        Menu("新建", systemImage: "plus") {
            ForEach([CountdownKind.anniversary, .countdown, .birthday, .holiday], id: \.self) { k in
                Button(k.name, systemImage: countdownSymbol(k)) {
                    editor = CountdownEditorTarget(countdownId: nil, kind: k)
                }
            }
        }
    }

    @ViewBuilder
    private func menu(_ c: Countdown) -> some View {
        Button(c.pinnedAt == nil ? "置顶" : "取消置顶", systemImage: c.pinnedAt == nil ? "pin" : "pin.slash") {
            onSave(togglingPin(c, now: clock()))
        }
        Button("编辑", systemImage: "pencil") { editor = CountdownEditorTarget(countdownId: c.id, kind: c.kind) }
        Menu("显示为", systemImage: "textformat.123") {
            Picker("显示为", selection: Binding(get: { format(c.id) }, set: { f in
                localFormats[c.id] = f
                onFormatChange(c.id, f)
            })) {
                Text("天数").tag(CountdownFormat.days)
                Text("年月天").tag(CountdownFormat.yearsMonthsDays)
                Text("周天").tag(CountdownFormat.weeksDays)
            }
            .pickerStyle(.inline)
        }
        Divider()
        Button("删除", systemImage: "trash", role: .destructive) { onSave(deletedCountdown(c, now: clock())) }
    }
}

struct CountdownEditorTarget: Identifiable, Hashable {
    var countdownId: String?
    var kind: CountdownKind
    var id: String { countdownId ?? "new-\(kind.rawValue)" }
}

// MARK: - Card

struct CountdownCard: View {
    @Environment(\.uiScale) private var s
    var countdown: Countdown
    var today: Day
    var format: CountdownFormat
    /// Tapping the number switches the format.
    var onSwitchFormat: () -> Void

    private var tint: Color { EfficiencyPalette.color(countdown.color) }

    var body: some View {
        let t = countdownCardText(countdown, today: today, format: format)
        VStack(spacing: 10 * s) {
            HStack(spacing: 6 * s) {
                EmojiBadge(emoji: countdown.emoji, color: countdown.color, fallback: countdownSymbol(countdown.kind), size: 24)
                Text(countdown.title).uiFont(.subheadline, weight: .semibold).lineLimit(1)
                if countdown.pinnedAt != nil {
                    Image(systemName: "pin.fill").uiFont(.caption2).foregroundStyle(.secondary).accessibilityLabel("已置顶")
                }
            }
            Button(action: onSwitchFormat) {
                VStack(spacing: 2 * s) {
                    if let caption = t.caption {
                        Text(caption).uiFont(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(" ").uiFont(.caption)
                    }
                    BigNumberText(runs: t.runs, tint: tint)
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityHint(Text("切换显示方式"))
            Text(t.date)
                .uiFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 18 * s)
        .padding(.horizontal, 12 * s)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground, in: .rect(cornerRadius: 18 * s))
        .accessibilityElement(children: .combine)
    }
}

/// "2个月22天" with the numbers big and the units small.
struct BigNumberText: View {
    var runs: [CountdownCardText.TextRun]
    var tint: Color
    /// At 标准; it grows with 界面大小.
    var size: CGFloat = 40
    @Environment(\.uiScale) private var s

    var body: some View {
        let size = size * s
        return runs.reduce(Text("")) { acc, r in
            let part = Text(r.text)
                .font(r.isNumber ? .system(size: size, weight: .semibold, design: .rounded) : .system(size: size * 0.4, weight: .medium))
                .foregroundStyle(r.isNumber ? tint : .secondary)
            return Text("\(acc)\(part)")
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .contentTransition(.numericText())
    }
}
