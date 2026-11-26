// 界面大小 (macOS): 小 / 标准 / 大 / 特大, in 设置 → 通用 and 显示 → 放大 ⌘+ /
// 缩小 ⌘- / 实际大小 ⌘0. Kept in this Mac's UserDefaults (`InterfacePrefs`),
// not synced. iOS and iPadOS follow the system's text size instead and
// always draw at 标准.
//
// macOS doesn't scale the system text styles with `.dynamicTypeSize` (nor
// `@ScaledMetric`), so the size is an environment value, `uiScale`, set once
// at the root of every window (`.interfaceScaleRoot()`: the main windows,
// the Settings window, the menu bar window, the quick-add panel). There it
// also sets the default font, the control size and the sidebar row size.
// At 标准 the scale is 1 and every helper returns exactly what the view
// asked for, so the default look doesn't change by a pixel.
//
// Writing a view so that it follows the size:
//
//     .uiFont(.body)                           not .font(.body)
//     .uiFont(.caption, weight: .semibold)     not .font(.caption.weight(.semibold))
//     .uiFont(size: 11, weight: .medium)       not .font(.system(size: 11, weight: .medium))
//     @Environment(\.uiScale) private var s    then  .frame(width: 16 * s), .padding(6 * s), spacing: 4 * s
//     @UIScaled private var box: CGFloat = 16  (like @ScaledMetric) for a stored size
//     Font.ui(.caption, scale: s)              when a Font value is needed (Text in Text, a stored font)
//     .uiDefaultFont(.headline)                on a Section's header (.subheadline: footer), whose
//                                              font the system picks only at 标准
//
// Text without a font of its own, SF Symbols in it, and the system's
// controls follow by themselves.

import SwiftUI
#if os(macOS)
import AppKit
#endif

public enum InterfaceSize: String, CaseIterable, Sendable, Hashable {
    case small, standard, large, extraLarge

    /// How much bigger than 标准 everything is drawn.
    public var scale: CGFloat {
        switch self {
        case .small: 0.9
        case .standard: 1
        case .large: 1.2
        case .extraLarge: 1.4
        }
    }

    public var title: String {
        switch self {
        case .small: "小"
        case .standard: "标准"
        case .large: "大"
        case .extraLarge: "特大"
        }
    }

    /// The next size up (放大 ⌘+), nil at 特大.
    public var larger: InterfaceSize? {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return i + 1 < all.count ? all[i + 1] : nil
    }

    /// The next size down (缩小 ⌘-), nil at 小.
    public var smaller: InterfaceSize? {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return i > 0 ? all[i - 1] : nil
    }

    /// What's stored; nil or anything unknown is 标准.
    public init(storage: String?) {
        self = storage.flatMap(InterfaceSize.init(rawValue:)) ?? .standard
    }

    /// The control size the system controls get at this size.
    var controlSize: ControlSize {
        switch self {
        case .small: .small
        case .standard: .regular
        // Not .extraLarge at 特大: it makes the switches twice as big and
        // the pop-up buttons' text no bigger.
        case .large, .extraLarge: .large
        }
    }

    /// The sidebars' row size at this size (标准 keeps the system's).
    var sidebarRowSize: SidebarRowSize {
        switch self {
        case .small: .small
        case .standard: .medium
        case .large, .extraLarge: .large
        }
    }
}

/// Where the size is kept: this Mac's UserDefaults, like `IntegrationPrefs`.
public enum InterfacePrefs {
    /// String, `InterfaceSize.rawValue`; missing means 标准.
    public static let sizeKey = "OTInterfaceSizeSetting"

    public static func size(_ defaults: UserDefaults = .standard) -> InterfaceSize {
        InterfaceSize(storage: defaults.string(forKey: sizeKey))
    }

    public static func setSize(_ size: InterfaceSize, _ defaults: UserDefaults = .standard) {
        if size == .standard {
            defaults.removeObject(forKey: sizeKey)
        } else {
            defaults.set(size.rawValue, forKey: sizeKey)
        }
    }

    /// 放大 (⌘+): one size up, nothing at 特大.
    public static func zoomIn(_ defaults: UserDefaults = .standard) {
        if let s = size(defaults).larger { setSize(s, defaults) }
    }

    /// 缩小 (⌘-): one size down, nothing at 小.
    public static func zoomOut(_ defaults: UserDefaults = .standard) {
        if let s = size(defaults).smaller { setSize(s, defaults) }
    }

    /// 实际大小 (⌘0): back to 标准.
    public static func resetSize(_ defaults: UserDefaults = .standard) {
        setSize(.standard, defaults)
    }

    /// Debug builds' `-OTInterfaceSize <size>`: this run uses that size,
    /// whatever is stored (it goes in the arguments domain, which UserDefaults
    /// reads first, so @AppStorage sees it too). Changing the size in the
    /// app doesn't show while it's there.
    public static func overrideForThisRun(_ size: InterfaceSize, _ defaults: UserDefaults = .standard) {
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments[sizeKey] = size.rawValue
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
}

extension EnvironmentValues {
    /// How much bigger than 标准 to draw: 1 on iOS and at 标准.
    @Entry public var uiScale: CGFloat = 1
}

extension Font {
    /// `style` at `scale` times its size: the text style itself at 1, so
    /// 标准 (and iOS, with its Dynamic Type) is exactly what it was.
    public static func ui(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil, scale: CGFloat) -> Font {
        if scale == 1 {
            let font = design.map { Font.system(style, design: $0) } ?? Font(style)
            return weight.map { font.weight($0) } ?? font
        }
        return .system(size: macPointSize(style) * scale, weight: weight ?? macWeight(style), design: design ?? .default)
    }

    /// A fixed size at `scale` times.
    public static func ui(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil, scale: CGFloat) -> Font {
        .system(size: size * scale, weight: weight, design: design)
    }

    private init(_ style: Font.TextStyle) {
        switch style {
        case .largeTitle: self = .largeTitle
        case .title: self = .title
        case .title2: self = .title2
        case .title3: self = .title3
        case .headline: self = .headline
        case .subheadline: self = .subheadline
        case .body: self = .body
        case .callout: self = .callout
        case .footnote: self = .footnote
        case .caption: self = .caption
        case .caption2: self = .caption2
        @unknown default: self = .body
        }
    }

    /// The text styles' sizes on macOS (`NSFont.preferredFont(forTextStyle:)`).
    static func macPointSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline: 13
        case .subheadline: 11
        case .body: 13
        case .callout: 12
        case .footnote: 10
        case .caption: 10
        case .caption2: 10
        @unknown default: 13
        }
    }

    private static func macWeight(_ style: Font.TextStyle) -> Font.Weight {
        switch style {
        case .headline: .bold
        case .caption2: .medium
        default: .regular
        }
    }
}

extension View {
    /// `.font(style)` that follows 界面大小. `adjust` is for what else the
    /// font had: `.uiFont(.title2) { $0.bold() }` for `.font(.title2.bold())`.
    public func uiFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil,
                       _ adjust: ((Font) -> Font)? = nil) -> some View {
        modifier(UIFont(kind: .style(style), weight: weight, design: design, adjust: adjust))
    }

    /// `.font(.system(size:weight:design:))` that follows 界面大小.
    public func uiFont(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil,
                       _ adjust: ((Font) -> Font)? = nil) -> some View {
        modifier(UIFont(kind: .size(size), weight: weight, design: design, adjust: adjust))
    }

    /// For text whose font the system picks (a `Section`'s header and
    /// footer, a sidebar's section titles): left to the system at 标准, but
    /// `style` scaled at the other sizes — under the root's bigger default
    /// font the system would draw it in that font, as big as the rows.
    public func uiDefaultFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(UIDefaultFont(style: style, weight: weight))
    }

    /// Sets 界面大小 for a window: once, at its root (`InterfaceScaleRoot`).
    public func interfaceScaleRoot() -> some View {
        modifier(InterfaceScaleRoot())
    }
}

private struct UIFont: ViewModifier {
    enum Kind { case style(Font.TextStyle), size(CGFloat) }
    let kind: Kind
    let weight: Font.Weight?
    let design: Font.Design?
    let adjust: ((Font) -> Font)?
    @Environment(\.uiScale) private var scale

    func body(content: Content) -> some View {
        let font: Font = switch kind {
        case .style(let style): .ui(style, weight: weight, design: design, scale: scale)
        case .size(let size): .ui(size: size, weight: weight, design: design, scale: scale)
        }
        content.font(adjust.map { $0(font) } ?? font)
    }
}

private struct UIDefaultFont: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?
    @Environment(\.uiScale) private var scale

    func body(content: Content) -> some View {
        // Not even `.font(nil)` at 标准: setting the font at all, to
        // anything, stops the system picking its own.
        if scale == 1 {
            content
        } else {
            content.font(.ui(style, weight: weight, scale: scale))
        }
    }
}

/// A size that follows 界面大小, like `@ScaledMetric`:
/// `@UIScaled private var box: CGFloat = 16`.
@propertyWrapper
public struct UIScaled: DynamicProperty {
    @Environment(\.uiScale) private var scale
    private let base: CGFloat

    public init(wrappedValue: CGFloat) {
        base = wrappedValue
    }

    public var wrappedValue: CGFloat { base * scale }
}

/// The one place 界面大小 comes in: reads the stored size (and follows
/// changes to it, so every open window changes at once) and sets the scale,
/// the default font, the control size and the sidebar row size under it.
///
/// At 标准 it sets nothing at all: writing even the value that's already
/// there makes it explicit, and an explicit control size changes how a
/// `Form` and the toolbar size their controls. So going between 标准 and
/// another size makes the window's views anew (the model — the module, the
/// view, the open task — stays; an edit in progress is saved as when the
/// detail closes).
struct InterfaceScaleRoot: ViewModifier {
    @AppStorage(InterfacePrefs.sizeKey) private var stored: String?

    func body(content: Content) -> some View {
        #if os(macOS)
        let size = InterfaceSize(storage: stored)
        if size == .standard {
            content
        } else {
            content
                .environment(\.uiScale, size.scale)
                .font(Font.ui(.body, scale: size.scale))
                .controlSize(size.controlSize)
                .environment(\.sidebarRowSize, size.sidebarRowSize)
        }
        #else
        content
        #endif
    }
}

#if os(macOS)
/// ⌘= for 放大 too: the menu item's ⌘+ is ⇧⌘= on most keyboards, and Mac
/// apps take ⌘= as well. Installed once, by the app at launch.
@MainActor
public enum InterfaceSizeKeys {
    private static var monitor: Any?

    public static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard flags == .command, event.charactersIgnoringModifiers == "=" else { return event }
            InterfacePrefs.zoomIn()
            return nil
        }
    }
}

/// 设置 → 通用 → 界面大小 (macOS; iOS follows the system's text size).
struct InterfaceSizeSection: View {
    @AppStorage(InterfacePrefs.sizeKey) private var stored: String?

    var body: some View {
        Section {
            Picker("界面大小", selection: Binding(
                get: { InterfaceSize(storage: stored) },
                set: { InterfacePrefs.setSize($0) }
            )) {
                ForEach(InterfaceSize.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("界面").uiDefaultFont(.headline)
        } footer: {
            Text("文字、图标和按钮一起变大变小，所有窗口立刻生效。也可以用“显示”菜单里的放大（⌘+）、缩小（⌘-）和实际大小（⌘0）。只在这台 Mac 上。")
                .uiDefaultFont(.subheadline)
        }
    }
}
#endif
