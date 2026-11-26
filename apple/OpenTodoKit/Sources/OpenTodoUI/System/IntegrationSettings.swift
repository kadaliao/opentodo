// 设置 → 快速添加 (macOS): the menu bar window on or off, and the global
// shortcut — on or off, and which keys (click the field, press the new
// combination; Esc stops). Kept in UserDefaults (this Mac's, not synced);
// `SystemServices` picks changes up as they're made.

#if os(macOS)
import AppKit
import OpenTodoSystem
import SwiftUI

public struct IntegrationSettingsPane: View {
    @AppStorage(IntegrationPrefs.menuBarKey) private var menuBar = true
    @AppStorage(IntegrationPrefs.hotKeyEnabledKey) private var hotKeyOn = true
    @AppStorage(IntegrationPrefs.hotKeyKey) private var hotKeyText = HotKey.quickAddDefault.storage

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle("在菜单栏显示", isOn: $menuBar)
            } header: {
                Group {
                    Text("菜单栏")
                }
                .uiDefaultFont(.headline)
            } footer: {
                Group {
                    Text("菜单栏里有今天的任务、快速添加和今天的专注时长。")
                }
                .uiDefaultFont(.subheadline)
            }
            Section {
                Toggle("用快捷键快速添加", isOn: $hotKeyOn)
                LabeledContent("快捷键") {
                    HotKeyRecorder(storage: $hotKeyText)
                }
                .disabled(!hotKeyOn)
                if hotKeyOn && SystemServices.shared.hotKeyFailed {
                    Label("这个快捷键被别的应用占用了，换一个试试", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } header: {
                Group {
                    Text("快速添加")
                }
                .uiDefaultFont(.headline)
            } footer: {
                Group {
                    Text("在任何应用里按下快捷键，屏幕上方会出现一行输入框，回车添加到收集箱（写了日期就按日期），Esc 取消。")
                }
                .uiDefaultFont(.subheadline)
            }
        }
        .formStyle(.grouped)
    }
}

/// Shows the shortcut; click, then press a new one.
struct HotKeyRecorder: View {
    @Environment(\.uiScale) private var s
    @Binding var storage: String
    @State private var recording = false
    @State private var hint: String?
    @State private var monitor: Any?

    private var current: HotKey { HotKey(storage: storage) ?? .quickAddDefault }

    var body: some View {
        HStack(spacing: 8 * s) {
            if let hint {
                Text(hint).uiFont(.caption).foregroundStyle(.secondary)
            }
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "按下新的快捷键…" : current.display)
                    .frame(minWidth: 110 * s)
            }
            .buttonStyle(.bordered)
            .tint(recording ? .accentColor : nil)
            if storage != HotKey.quickAddDefault.storage && !recording {
                Button("恢复默认") { storage = HotKey.quickAddDefault.storage }
                    .buttonStyle(.borderless)
                    .uiFont(.caption)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        hint = "要带 ⌃、⌥ 或 ⌘"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53 && flags.intersection([.control, .option, .command]).isEmpty { // Esc
                stop()
                return nil
            }
            var mods: HotKey.Modifiers = []
            if flags.contains(.control) { mods.insert(.control) }
            if flags.contains(.option) { mods.insert(.option) }
            if flags.contains(.shift) { mods.insert(.shift) }
            if flags.contains(.command) { mods.insert(.command) }
            let key = HotKey(keyCode: UInt32(event.keyCode), modifiers: mods,
                             keyName: HotKey.keyName(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers))
            if key.isValid {
                storage = key.storage
                stop()
            } else {
                hint = "要带 ⌃、⌥ 或 ⌘"
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        hint = nil
    }
}
#endif
