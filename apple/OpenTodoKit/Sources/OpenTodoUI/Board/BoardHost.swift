// The board in the app: a list (or the inbox) laid out as a board
// (`TaskListArea` → `LayoutContent`, layout 看板). The data comes from the
// model's snapshot (`boardColumns`), the board's callbacks go to TaskRepo
// through the model: drops (`dropInto`), quick add in a column, ticking off
// (with the undo for a repeating task), opening and picking cards
// (`model.selection`), and the section menu and dialogs (the app's own).

import OpenTodoData
import OpenTodoDomain
import SwiftUI

extension AppModel {
    /// How `view` (a list or the inbox) orders its board.
    func boardSort(_ view: ViewRef) -> TaskSort { prefs(for: view).sortIn(view) ?? .manual }

    /// The board of `view`: a column per section of its list.
    func boardColumns(_ view: ViewRef) -> [BoardColumn] {
        guard let listId = arrangedListId(view) else { return [] }
        return OpenTodoDomain.boardColumns(listId, data.tasks, sectionsByList[listId] ?? [], sort: boardSort(view))
    }

    /// Which cards show as selected: the picked ones while picking, else the
    /// open one.
    var boardSelection: BoardSelection {
        BoardSelection(open: selectedTaskId, picked: selection.ids, picking: selection.isActive || selection.isPicking)
    }

    /// A click or tap on a task shown in `order` (`tapTask`): ⌘ / ⇧ pick,
    /// a plain click opens.
    func tapTask(_ id: String, modifiers: EventModifiers, order: [String]) {
        var tap: TapModifiers = []
        if modifiers.contains(.command) { tap.insert(.command) }
        if modifiers.contains(.shift) { tap.insert(.shift) }
        if let open = selection.tap(id, modifiers: tap, order: order, current: selectedTaskId) {
            self.open(taskId: open)
        }
    }

    /// Tasks dropped into a group (a board column, a list's section, a day,
    /// a priority…): they take on what it stands for, and land where they
    /// were dropped in manual order. The picked ones stay picked.
    func dropTasks(_ plan: TaskDropPlan) async {
        await attempt { try await repo.dropInto(plan.ids, plan.target, plan.orders) }
    }

    /// Writes what was done to a list's sections. Adding one shows the
    /// list's sections again if it was grouped some other way, so the new
    /// one is there to see (as `askAddSection` does).
    func perform(_ action: SectionAction) async {
        switch action {
        case let .add(listId, name):
            await attempt { _ = try await repo.addSection(listId, name) }
            let view: ViewRef = listId == inboxListId ? .smart(.inbox) : .list(listId)
            if prefs(for: view).groupingIn(view) != .sections { settings.setGrouping(view, .sections) }
        case let .rename(id, name):
            await attempt { try await repo.updateSection(id, name: name) }
        case .reorder(let orders):
            await attempt {
                for (id, order) in orders { try await repo.updateSection(id, sortOrder: order) }
            }
        case .delete(let id):
            await attempt { try await repo.deleteSection(id) }
        }
    }

    /// Shows the app's dialog for a section (they write when confirmed).
    func ask(_ dialog: SectionDialog) {
        switch dialog {
        case .add(let listId): askAddSection(listId)
        case .rename(let s): askRenameSection(s)
        case .delete(let s): askDeleteSection(s)
        }
    }

    /// What the board of `view` does when the person acts on it.
    func boardActions(_ view: ViewRef, order: [String]) -> BoardActions {
        BoardActions(
            tap: { [weak self] id, modifiers in self?.tapTask(id, modifiers: modifiers, order: order) },
            setDone: { [weak self] task, done in self?.run { await self?.setDone(task, done) } },
            quickAdd: { [weak self] q in
                self?.run { _ = await self?.quickAdd(q.text, target: QuickAddTarget(listId: q.listId, sectionId: q.sectionId)) }
            },
            drop: { [weak self] plan in self?.run { await self?.dropTasks(plan) } },
            section: { [weak self] action in self?.run { await self?.perform(action) } },
            askSection: { [weak self] dialog in self?.ask(dialog) }
        )
    }
}

/// `view`'s list as a board.
struct ListBoard: View {
    @Environment(AppModel.self) private var model
    var view: ViewRef

    var body: some View {
        let columns = model.boardColumns(view)
        if let listId = arrangedListId(view) {
            BoardView(
                listId: listId,
                columns: columns,
                sort: model.boardSort(view),
                now: model.now,
                selection: model.boardSelection,
                progress: ChecklistProgress.of(model.data.checklistItems),
                actions: model.boardActions(view, order: BoardLayout.taskOrder(columns))
            ) { task in
                TaskMenu(task: task)
            }
            .selectAllTasksShortcut { model.boardOrder(view) }
        }
    }
}
