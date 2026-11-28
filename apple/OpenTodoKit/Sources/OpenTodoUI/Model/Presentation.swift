// Dialogs and sheets the window should show. Anything can ask by setting a
// request (`model.present.confirm = ConfirmRequest(…)`); `DialogHost`
// (Shell/DialogHost.swift) at the root shows each one. A request carries
// its own completion, so the asker needn't stay on screen.
//
// To add a dialog: a request type and a property here, and one modifier in
// `DialogHost`.

import Foundation
import Observation
import OpenTodoDomain

/// 确定 / 取消, e.g. 删除清单“工作”？
public struct ConfirmRequest: Identifiable {
    public let id = UUID()
    public var title: String
    public var message: String?
    public var action: String
    public var destructive: Bool
    public var onConfirm: @MainActor () -> Void

    public init(title: String, message: String? = nil, action: String = "确定", destructive: Bool = false,
                onConfirm: @escaping @MainActor () -> Void) {
        self.title = title
        self.message = message
        self.action = action
        self.destructive = destructive
        self.onConfirm = onConfirm
    }
}

/// One line of text: a section's name, a new tag.
public struct TextPromptRequest: Identifiable {
    public let id = UUID()
    public var title: String
    public var placeholder: String
    public var initial: String
    public var action: String
    /// Tags to offer under the field, narrowed as it's typed
    /// (`tagSuggestions`); picking one submits it. Empty: none.
    public var suggestions: [String]
    public var onSubmit: @MainActor (String) -> Void

    public init(title: String, placeholder: String, initial: String = "", action: String = "确定",
                suggestions: [String] = [], onSubmit: @escaping @MainActor (String) -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.initial = initial
        self.action = action
        self.suggestions = suggestions
        self.onSubmit = onSubmit
    }
}

/// The list editor: a new list (nil) or this one.
public struct ListEditorRequest: Identifiable {
    public let id = UUID()
    public var list: TaskList?
    /// The icon tab to open on (the `list-editor:` debug route); nil: the
    /// one the list's icon is on.
    var tab: ListEditorSheet.Tab?

    public init(list: TaskList? = nil) { self.list = list }

    init(list: TaskList?, tab: ListEditorSheet.Tab?) {
        self.list = list
        self.tab = tab
    }
}

/// The date dialog for a task, from somewhere without a button to anchor a
/// popover to (a context menu). The detail's date row uses the
/// `.scheduleEditor` modifier directly.
public struct ScheduleRequest: Identifiable {
    public let id = UUID()
    public var taskId: String

    public init(taskId: String) { self.taskId = taskId }
}

/// The filter editor (the search engineer's): a new filter (nil) or this one.
public struct FilterEditorRequest: Identifiable {
    public let id = UUID()
    public var filter: TaskFilter?

    public init(filter: TaskFilter? = nil) { self.filter = filter }
}

@Observable
public final class Presentation {
    public var confirm: ConfirmRequest?
    public var textPrompt: TextPromptRequest?
    public var listEditor: ListEditorRequest?
    public var schedule: ScheduleRequest?
    public var filterEditor: FilterEditorRequest?
    /// iOS: the settings sheet (macOS has a Settings window).
    public var settings = false
    /// iPhone: the quick-add sheet.
    public var quickAdd = false

    public init() {}
}
