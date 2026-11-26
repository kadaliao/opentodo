// Small pieces the four efficiency modules (习惯, 专注, 倒数日, 四象限)
// share: colours stored as ARGB, the emoji and colour pickers, time and
// date text, and Day ⇄ Date bindings for the system date pickers.

import OpenTodoDomain
import SwiftUI

// MARK: - Clock

/// Epoch milliseconds now: what records stamp `createdAt` / `updatedAt`
/// with. Components take a `clock` so tests and previews can pin it.
func millisNow() -> Int { Int((Date.now.timeIntervalSince1970 * 1000).rounded()) }

// MARK: - Colours

extension Color {
    /// A colour stored as ARGB (`TaskList.color`, Flutter's `Color.value`).
    init(argb: Int) {
        let v = UInt32(truncatingIfNeeded: argb)
        self.init(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255,
            opacity: Double((v >> 24) & 0xFF) / 255
        )
    }
}

/// The colours a habit or a countdown can take: the system palette.
enum EfficiencyPalette {
    static let colors: [Int] = [
        0xFF14A38B, // the app's accent
        0xFFFF3B30, 0xFFFF9500, 0xFFFFCC00, 0xFF34C759, 0xFF00C7BE,
        0xFF32ADE6, 0xFF007AFF, 0xFF5856D6, 0xFFAF52DE, 0xFFFF2D55, 0xFFA2845E,
    ]

    static func color(_ argb: Int?) -> Color { argb.map(Color.init(argb:)) ?? .accentColor }
}

/// A row of colour dots; the chosen one has a ring.
struct ColorDotsPicker: View {
    @Binding var color: Int?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 10)], spacing: 10) {
            ForEach(EfficiencyPalette.colors, id: \.self) { c in
                Button {
                    color = c
                } label: {
                    Circle()
                        .fill(Color(argb: c))
                        .frame(width: 24, height: 24)
                        .padding(3)
                        .overlay {
                            if (color ?? EfficiencyPalette.colors[0]) == c {
                                Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("颜色"))
                .accessibilityAddTraits((color ?? EfficiencyPalette.colors[0]) == c ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// An emoji on a tinted circle: a habit's or a countdown's badge.
struct EmojiBadge: View {
    var emoji: String?
    var color: Int?
    var fallback: String = "star.fill"
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(EfficiencyPalette.color(color).opacity(0.18))
            if let emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: size * 0.55))
            } else {
                Image(systemName: fallback)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(EfficiencyPalette.color(color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Picks an emoji from a short list, or takes one typed in.
struct EmojiPickerButton: View {
    @Binding var emoji: String?
    var color: Int?
    var fallback: String
    @State private var showing = false
    @State private var typed = ""

    static let choices = [
        "💧", "🏃", "📖", "🧘", "💪", "🍎", "🥗", "😴", "🦷", "💊", "✍️", "🎹",
        "🎂", "❤️", "🎉", "✈️", "🎓", "💼", "🏠", "🎄", "🧧", "🌕", "⭐️", "🔔",
    ]

    var body: some View {
        Button {
            showing = true
        } label: {
            EmojiBadge(emoji: emoji, color: color, fallback: fallback, size: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("图标"))
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 6), spacing: 6) {
                    ForEach(Self.choices, id: \.self) { e in
                        Button {
                            emoji = e
                            showing = false
                        } label: {
                            Text(e).font(.title2).frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("其他", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .onSubmit(takeTyped)
                    Button("用这个", action: takeTyped).disabled(typed.isEmpty)
                    Spacer()
                    Button("不用图标") {
                        emoji = nil
                        showing = false
                    }
                }
                .font(.callout)
            }
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }

    private func takeTyped() {
        guard let first = typed.first else { return }
        emoji = String(first)
        typed = ""
        showing = false
    }
}

// MARK: - Text

/// 25:00 / 1:02:03, for a running clock.
func clockText(_ seconds: Int) -> String {
    let s = max(seconds, 0)
    let h = s / 3600, m = s % 3600 / 60, sec = s % 60
    func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    return h > 0 ? "\(h):\(two(m)):\(two(sec))" : "\(two(m)):\(two(sec))"
}

/// 1小时25分 / 25分 / 0分: focus totals.
func durationText(_ seconds: Int) -> String {
    let m = max(seconds, 0) / 60
    if m >= 60 { return m % 60 == 0 ? "\(m / 60)小时" : "\(m / 60)小时\(m % 60)分" }
    return "\(m)分"
}

/// 11月26日 周四; with the year when it isn't `today`'s.
func dayText(_ d: Day, today: Day? = nil) -> String {
    let base = "\(d.month)月\(d.day)日 \(weekdayName(d))"
    if let today, today.year != d.year { return "\(d.year)年" + base }
    return base
}

/// 一 … 日 for a week strip.
func weekdayLetter(_ d: Day) -> String { String(weekdayName(d).dropFirst()) }

/// A number without a pointless `.0`: 8, 2.5.
func amountText(_ v: Double) -> String {
    v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
}

// MARK: - Day ⇄ Date

extension Binding where Value == Day {
    /// For a `DatePicker`: the day's midnight in the current time zone.
    var date: Binding<Date> {
        Binding<Date>(
            get: { wrappedValue.start() },
            set: { wrappedValue = Day($0) }
        )
    }
}

extension Binding where Value == Int {
    /// Minutes after midnight as a `Date` today, for an hour-and-minute
    /// `DatePicker`.
    var timeOfDay: Binding<Date> {
        Binding<Date>(
            get: { LocalDateTime(Day.today(), minute: wrappedValue).date() },
            set: { wrappedValue = LocalDateTime($0).minuteOfDay }
        )
    }
}

// MARK: - Layout

/// A rounded panel on the grouped background: the cards of these modules.
struct PanelBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.cardBackground, in: .rect(cornerRadius: 16))
    }
}

extension View {
    func panel(padding: CGFloat = 16) -> some View { modifier(PanelBackground(padding: padding)) }
}

extension Color {
    /// The background behind panels (a grouped list's).
    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// A panel on `groupedBackground` (a grouped list's cells).
    static var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// The actions after a screen's main one: on iOS in the toolbar's …
    /// menu (`.secondaryAction`); on the Mac beside the main one at the end
    /// of the toolbar, since there `.secondaryAction` sits in the middle.
    static var moreActions: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .secondaryAction
        #endif
    }
}
