// A global keyboard shortcut (macOS 快速添加, ⌃⇧A out of the box): which
// key, which modifiers, how it reads (⌃⇧A) and how it is stored in the
// app's preferences. Registering it with the system is
// `OpenTodoUI/System/GlobalHotKey.swift` (Carbon `RegisterEventHotKey`);
// this part is plain values, for tests.

import Foundation

public struct HotKey: Hashable, Sendable, Codable {
    public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    /// The virtual key code (kVK_…), layout-independent.
    public var keyCode: UInt32
    public var modifiers: Modifiers
    /// What the key shows as (A, 1, Space), taken when it was recorded.
    public var keyName: String

    public init(keyCode: UInt32, modifiers: Modifiers, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    /// ⌃⇧A: control-shift-A (kVK_ANSI_A is 0).
    public static let quickAddDefault = HotKey(keyCode: 0, modifiers: [.control, .shift], keyName: "A")

    /// ⌃⌥⇧⌘ then the key, in the order the system's menus use.
    public var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + keyName
    }

    /// A global shortcut needs ⌃, ⌥ or ⌘ (shift alone would eat typing).
    public var isValid: Bool { !modifiers.intersection([.control, .option, .command]).isEmpty }

    /// Carbon's modifier mask for `RegisterEventHotKey` (cmdKey 0x100,
    /// shiftKey 0x200, optionKey 0x800, controlKey 0x1000).
    public var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= 0x100 }
        if modifiers.contains(.shift) { m |= 0x200 }
        if modifiers.contains(.option) { m |= 0x800 }
        if modifiers.contains(.control) { m |= 0x1000 }
        return m
    }

    /// What a key shows as in a shortcut: the special keys by name (kVK
    /// codes), anything else as its character, upper-cased.
    public static func keyName(keyCode: UInt16, characters: String?) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 117: return "⌦"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "↖"
        case 119: return "↘"
        case 116: return "⇞"
        case 121: return "⇟"
        default: break
        }
        let functionKeys: [UInt16: Int] = [122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10, 103: 11, 111: 12]
        if let n = functionKeys[keyCode] { return "F\(n)" }
        let c = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return c.isEmpty ? "#\(keyCode)" : c
    }

    // MARK: Stored

    /// `<keyCode>:<modifiers>:<keyName>`, e.g. `0:5:A`.
    public var storage: String { "\(keyCode):\(modifiers.rawValue):\(keyName)" }

    /// Nil for text that isn't one (or a shortcut without ⌃ ⌥ ⌘).
    public init?(storage: String) {
        let parts = storage.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let code = UInt32(parts[0]), let mods = Int(parts[1]), !parts[2].isEmpty else { return nil }
        self.init(keyCode: code, modifiers: Modifiers(rawValue: mods & 0xF), keyName: String(parts[2]))
        guard isValid else { return nil }
    }
}

/// The macOS-only preferences of the system integration, kept in the
/// app's UserDefaults (they belong to this Mac, not the account).
public enum IntegrationPrefs {
    /// Bool, default true: the menu bar window.
    public static let menuBarKey = "OTMenuBarEnabled"
    /// Bool, default true: the global quick-add shortcut.
    public static let hotKeyEnabledKey = "OTQuickAddHotKeyEnabled"
    /// String, `HotKey.storage`; missing means ⌃⇧A.
    public static let hotKeyKey = "OTQuickAddHotKey"

    public static func hotKey(_ defaults: UserDefaults = .standard) -> HotKey? {
        guard defaults.object(forKey: hotKeyEnabledKey) as? Bool ?? true else { return nil }
        return defaults.string(forKey: hotKeyKey).flatMap(HotKey.init(storage:)) ?? .quickAddDefault
    }
}
