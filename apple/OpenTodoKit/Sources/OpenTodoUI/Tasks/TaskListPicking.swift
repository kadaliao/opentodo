// Picking tasks in the list (多选, docs/architecture.md): the system list's
// own multiple selection does the clicking — ⌘-click adds or removes (the
// open task comes along the first time), Shift-click picks the range as
// shown (folded groups aren't in the list), ⌘A picks all unless a text
// field has the cursor — and the result goes into `model.selection`. One
// task without ⌘ / Shift just opens it. Esc clears. On iPhone, 多选 in a
// row's long-press menu turns on the list's edit mode, where a tap picks.
// Nothing is picked in the trash.

import OpenTodoDomain
import SwiftUI
#if os(macOS)
import AppKit
#endif

extension AppModel {
    /// The list's selection: the picked tasks while picking, else the open one.
    func listSelection(in view: ViewRef) -> Binding<Set<String>> {
        Binding(get: { [self] in
            selection.isActive || selection.isPicking ? selection.ids : Set(selectedTaskId.map { [$0] } ?? [])
        }, set: { [self] new in
            let current: Set<String> = selection.isActive ? selection.ids : Set(selectedTaskId.map { [$0] } ?? [])
            guard canPick(in: view) else {
                // Only ever one: the row just clicked (⌘A picks nothing here, as in Flutter).
                if new.subtracting(current).count > 1 { return }
                if let id = new.subtracting(current).first ?? new.first { open(taskId: id) } else { selectedTaskId = nil }
                return
            }
            // ⌘-click with nothing open starts picking with that one (Flutter's tapTask).
            if selection.isPicking || (new.count > 1)
                || Self.extendingClick && (selection.isActive || (current.isEmpty && !new.isEmpty)) {
                selection.replace(with: new)
            } else {
                selection.clear()
                if let id = new.first { open(taskId: id) } else { selectedTaskId = nil }
            }
        })
    }

    /// Whether ⌘ or Shift is held (a click that edits the selection).
    static var extendingClick: Bool {
        #if os(macOS)
        !NSEvent.modifierFlags.intersection([.command, .shift]).isEmpty
        #else
        false
        #endif
    }
}

/// Esc, the iPhone edit mode and bottom bar, and 完成 to stop picking —
/// or sorting (iOS 排序, TaskListDrag.swift: each row shows its ≡).
struct TaskListPicking: ViewModifier {
    @Environment(AppModel.self) private var model
    var view: ViewRef

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onExitCommand { model.selection.clear() }
        #else
        let sorting = model.taskList.isSorting(view)
        content
            .environment(\.editMode, .constant(model.selection.isPicking ? .active : .inactive))
            .batchBottomBar(selection: model.width == .compact && model.selection.isPicking
                                ? model.batchSelection ?? BatchSelection(ids: [], tasks: []) : nil,
                            lists: model.lists, knownTags: model.tags, today: model.today) { action in
                model.run { await model.performBatch(action) }
            }
            .toolbar {
                if model.selection.isPicking {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { model.selection.clear() }
                    }
                } else if sorting {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { model.taskList.stopSorting() }
                    }
                }
            }
            // 排序 is for the view on screen: it stops on leaving it.
            .onChange(of: view) { model.taskList.stopSorting() }
            .onDisappear { if model.taskList.isSorting(view) { model.taskList.stopSorting() } }
        #endif
    }
}

/// The detail column while tasks are picked: the batch panel.
struct BatchDetail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let picked = model.batchSelection {
            BatchPanel(selection: picked, lists: model.lists, knownTags: model.tags, today: model.today) { action in
                model.run { await model.performBatch(action) }
            }
        }
    }
}
