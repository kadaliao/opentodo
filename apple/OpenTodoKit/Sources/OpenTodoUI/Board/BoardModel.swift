// The board's inputs and outputs, and the little it works out for itself
// (pure, tested): how wide a column is, the order cards are picked in,
// which cards go together in a drag.

import CoreGraphics
import OpenTodoDomain
import SwiftUI

/// Which cards are selected: the one open in the detail, or the picked ones
/// (多选) while picking.
public struct BoardSelection: Hashable, Sendable {
    /// The task open in the detail.
    public var open: String?
    /// The picked tasks (多选).
    public var picked: Set<String>
    /// Picking is on: a card is selected when it's picked, whatever is
    /// open. On by itself when something is picked.
    public var picking: Bool

    public init(open: String? = nil, picked: Set<String> = [], picking: Bool? = nil) {
        self.open = open
        self.picked = picked
        self.picking = picking ?? !picked.isEmpty
    }

    public func isSelected(_ id: String) -> Bool { picking ? picked.contains(id) : open == id }
}

/// How far a task's checklist (子任务) is done.
public struct ChecklistProgress: Hashable, Sendable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    /// Progress for each task with a checklist.
    public static func of(_ items: [ChecklistItem]) -> [String: ChecklistProgress] {
        var out: [String: ChecklistProgress] = [:]
        for item in items where item.deletedAt == nil {
            out[item.taskId, default: ChecklistProgress(done: 0, total: 0)].total += 1
            if item.done { out[item.taskId]!.done += 1 }
        }
        return out
    }
}

/// A task typed into a column's own field: it goes in that column's
/// section of the list. `text` is as typed (the quick-add parser still
/// reads dates and tags out of it).
public struct BoardQuickAdd: Hashable, Sendable {
    public var text: String
    public var listId: String
    /// Nil for 未分组.
    public var sectionId: String?

    public init(text: String, listId: String, sectionId: String?) {
        self.text = text
        self.listId = listId
        self.sectionId = sectionId
    }
}

/// What the person did on the board. Every closure has a do-nothing default.
public struct BoardActions {
    /// A card was clicked or tapped, with the keys held (⌘ / ⇧ on a Mac;
    /// none on a touch screen). The caller opens it or picks it, in
    /// `BoardLayout.taskOrder`.
    public var tap: (_ taskId: String, _ modifiers: EventModifiers) -> Void
    /// A card's box was ticked or unticked.
    public var setDone: (_ task: TodoTask, _ done: Bool) -> Void
    public var quickAdd: (BoardQuickAdd) -> Void
    /// Cards were dropped: `TaskRepo.dropInto(plan.ids, plan.target, plan.orders)`.
    public var drop: (TaskDropPlan) -> Void
    /// A section was added, renamed, moved or deleted.
    public var section: (SectionAction) -> Void
    /// Asks for a section dialog (添加分组, 重命名, 删除) to be shown by the
    /// app's own dialogs; nil: the board shows its own and reports the
    /// outcome through `section`.
    public var askSection: ((SectionDialog) -> Void)?

    /// Where a section dialog the board asks for goes: to the app's
    /// dialogs (`askSection`, and nil comes back), or back to the board to
    /// show its own.
    public func route(_ dialog: SectionDialog) -> SectionDialog? {
        guard let askSection else { return dialog }
        askSection(dialog)
        return nil
    }

    public init(
        tap: @escaping (_ taskId: String, _ modifiers: EventModifiers) -> Void = { _, _ in },
        setDone: @escaping (_ task: TodoTask, _ done: Bool) -> Void = { _, _ in },
        quickAdd: @escaping (BoardQuickAdd) -> Void = { _ in },
        drop: @escaping (TaskDropPlan) -> Void = { _ in },
        section: @escaping (SectionAction) -> Void = { _ in },
        askSection: ((SectionDialog) -> Void)? = nil
    ) {
        self.askSection = askSection
        self.tap = tap
        self.setDone = setDone
        self.quickAdd = quickAdd
        self.drop = drop
        self.section = section
    }
}

public enum BoardLayout {
    /// A column on a wide screen.
    public static let columnWidth: CGFloat = 272
    /// Narrower than this is a phone (Flutter's `Breakpoints.twoPane`).
    public static let phoneWidth: CGFloat = 640

    /// How wide a column is on a board `width` wide: a phone shows one
    /// column and a bit of the next. Zero (not measured yet) is wide.
    public static func columnWidth(for width: CGFloat) -> CGFloat {
        width > 0 && width < phoneWidth ? (width * 0.82).rounded(.down) : columnWidth
    }

    /// Every card's task, column by column, open ones then finished: the
    /// order ⌘ / ⇧ clicks pick in.
    public static func taskOrder(_ columns: [BoardColumn]) -> [String] {
        columns.flatMap { $0.group.tasks.map(\.id) + $0.done.map(\.id) }
    }

    /// The picked open cards, in board order: they're dragged together.
    public static func picked(_ columns: [BoardColumn], _ selection: BoardSelection) -> [TodoTask] {
        guard selection.picking else { return [] }
        return columns.flatMap { $0.group.tasks.filter { selection.picked.contains($0.id) } }
    }

    /// The list's sections, in the board's order.
    public static func sections(_ columns: [BoardColumn]) -> [ListSection] {
        columns.compactMap(\.group.section)
    }

    /// What a drop in `column` does.
    public static func drop(_ column: BoardColumn, listId: String, sort: TaskSort) -> GroupDrop {
        GroupDrop(.section(listId: listId, sectionId: column.group.section?.id), tasks: column.group.tasks, manual: sort == .manual)
    }

    /// What typing `text` into `column`'s own field adds; nil when there's
    /// nothing but spaces.
    public static func quickAdd(_ text: String, in column: BoardColumn, listId: String) -> BoardQuickAdd? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? nil : BoardQuickAdd(text: typed, listId: listId, sectionId: column.group.section?.id)
    }

    /// A column's id: its section's, or `none` for 未分组.
    public static func key(_ column: BoardColumn) -> String { column.group.section?.id ?? "none" }
}
