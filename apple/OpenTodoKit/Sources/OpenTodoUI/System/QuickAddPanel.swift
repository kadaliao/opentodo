// macOS: the quick-add line the global shortcut (⌃⇧A) brings up over every
// app, like Spotlight: a floating panel that takes the keyboard without
// bringing OpenTodo forward. It is the tasks module's own quick-add field
// (`QuickAddField`: parsing and highlight included), adding to the inbox
// unless the text names a date. Return adds and closes; Esc, the shortcut
// again or a click elsewhere closes.

#if os(macOS)
import AppKit
import OpenTodoSystem
import SwiftUI

@MainActor
final class QuickAddPanelController {
    static let shared = QuickAddPanelController()

    private var panel: QuickAddPanel?
    private let state = QuickAddPanelState()

    func toggle(model: AppModel) {
        if let panel, panel.isVisible { close() } else { show(model: model) }
    }

    func show(model: AppModel) {
        let panel = self.panel ?? make(model: model)
        self.panel = panel
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.68))
        }
        state.shows += 1
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func make(model: AppModel) -> QuickAddPanel {
        let panel = QuickAddPanel(
            contentRect: NSRect(x: 0, y: 0, width: QuickAddPanelView.width, height: QuickAddPanelView.height),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.onClose = { [weak self] in self?.close() }
        let view = QuickAddPanelView(state: state) { [weak self] in self?.close() }
            .environment(model)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: QuickAddPanelView.width, height: QuickAddPanelView.height)
        panel.contentView = host
        return panel
    }
}

/// Counts the times the panel was shown, so the field takes focus each time.
@MainActor @Observable
final class QuickAddPanelState {
    var shows = 0
}

final class QuickAddPanel: NSPanel {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc.
    override func cancelOperation(_ sender: Any?) { onClose?() }

    /// A click elsewhere.
    override func resignKey() {
        super.resignKey()
        onClose?()
    }
}

struct QuickAddPanelView: View {
    static let width: CGFloat = 640
    static let height: CGFloat = 64

    let state: QuickAddPanelState
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            QuickAddField(prompt: "添加任务：明天下午3点开会 #工作 !高", focusRequests: state.shows) { _ in close() }
        }
        .padding(.horizontal, 20)
        .frame(width: Self.width, height: Self.height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onExitCommand(perform: close)
    }
}
#endif
