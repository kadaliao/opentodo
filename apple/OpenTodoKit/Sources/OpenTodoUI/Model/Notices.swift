// Short notes at the bottom of the window — 已完成，下次：后天 · 撤销,
// 已删除 · 撤销, 已添加到明天 — shown by `NoticeBanner`, gone after a few
// seconds. A note with an undo also registers it with the window's
// `UndoManager`, so ⌘Z (and shake on iPhone) does the same.

import Foundation
import Observation

public struct Notice: Identifiable, Sendable {
    public let id = UUID()
    public var text: String
    /// The button's label, 撤销 by default.
    public var actionLabel: String
    public var action: (@MainActor @Sendable () async -> Void)?
}

@Observable
public final class Notices {
    public private(set) var current: Notice?
    /// The window's undo manager, set by the root view.
    @ObservationIgnored public weak var undoManager: UndoManager?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    public init() {}

    /// Shows `text`; with `undo`, a 撤销 button (and ⌘Z) that runs it once.
    public func show(_ text: String, undoName: String? = nil, undo: (@MainActor @Sendable () async -> Void)? = nil) {
        let notice = Notice(text: text, actionLabel: "撤销", action: undo)
        current = notice
        if let undo, let undoManager {
            undoManager.registerUndo(withTarget: self) { notices in
                notices.dismiss(notice.id)
                Task { @MainActor in await undo() }
            }
            undoManager.setActionName(undoName ?? text)
        }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(undo == nil ? 3 : 5))
            guard !Task.isCancelled else { return }
            self?.dismiss(notice.id)
        }
    }

    /// Runs the current notice's action and hides it.
    public func runAction() async {
        guard let notice = current, let action = notice.action else { return }
        dismiss(notice.id)
        undoManager?.removeAllActions(withTarget: self)
        await action()
    }

    public func dismiss(_ id: UUID? = nil) {
        if id == nil || current?.id == id { current = nil }
    }
}
