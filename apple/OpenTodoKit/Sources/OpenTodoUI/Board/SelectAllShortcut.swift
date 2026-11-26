// ⌘A on the board and the timeline: picks every task the view shows, in
// its order (`model.selection.selectAll`), as the system list does by
// itself. While a text field has the keyboard (a column's quick-add field,
// say), ⌘A is the field's: it selects its text.

import OpenTodoDomain
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Who a ⌘A is for.
enum SelectAllTarget: Equatable {
    /// The focused text field: select its text.
    case text
    /// The view's tasks.
    case tasks

    static func resolve(textFocused: Bool) -> SelectAllTarget { textFocused ? .text : .tasks }
}

extension AppModel {
    /// The tasks of `view`'s board, in the order shown (column by column).
    func boardOrder(_ view: ViewRef) -> [String] { BoardLayout.taskOrder(boardColumns(view)) }

    /// The tasks of `view`'s timeline, in the order shown: the undated
    /// ones, then lane by lane.
    func timelineOrder(_ view: ViewRef) -> [String] {
        let t = timeline(for: view)
        return t.undatedTasks.map(\.id) + t.lanes.flatMap { $0.bars.map(\.task.id) }
    }

    /// ⌘A: picks all of `order`, unless a text field has the keyboard.
    func selectAllTasks(_ order: [String], textFocused: Bool) {
        guard SelectAllTarget.resolve(textFocused: textFocused) == .tasks, !order.isEmpty else { return }
        selection.selectAll(order)
    }
}

extension View {
    /// ⌘A picks the tasks `order` gives (worked out when pressed).
    func selectAllTasksShortcut(_ order: @escaping () -> [String]) -> some View {
        modifier(SelectAllTasksShortcut(order: order))
    }
}

private struct SelectAllTasksShortcut: ViewModifier {
    @Environment(AppModel.self) private var model
    let order: () -> [String]

    func body(content: Content) -> some View {
        content.background {
            Button("全选") {
                let textFocused = TextFocus.isTextFocused
                if textFocused { TextFocus.selectAllText() }
                model.selectAllTasks(order(), textFocused: textFocused)
            }
            .keyboardShortcut("a", modifiers: .command)
            .hidden()
            .accessibilityHidden(true)
        }
    }
}

/// Whether a text field or text view has the keyboard, and selecting its
/// text.
@MainActor private enum TextFocus {
    #if os(macOS)
    static var isTextFocused: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    static func selectAllText() {
        NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
    }
    #else
    static var isTextFocused: Bool {
        FirstResponder.find() is UITextInput
    }

    static func selectAllText() {
        UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
    }
    #endif
}

#if os(iOS)
/// The first responder, found by sending an action to nil: the first one
/// gets it and says so.
@MainActor private final class FirstResponder {
    static weak var current: UIResponder?

    static func find() -> UIResponder? {
        current = nil
        UIApplication.shared.sendAction(#selector(UIResponder.otReportFirstResponder), to: nil, from: nil, for: nil)
        return current
    }
}

extension UIResponder {
    @objc fileprivate func otReportFirstResponder() {
        FirstResponder.current = self
    }
}
#endif
