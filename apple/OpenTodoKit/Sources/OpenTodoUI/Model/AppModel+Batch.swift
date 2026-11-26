// Multi-select in the task list and the batch actions (batch_actions.dart):
// which tasks are shown in order (for Shift ranges and 全选), the picked
// tasks as the batch views want them, and each `BatchAction` run through
// TaskRepo one task at a time. 完成 and 删除 clear the selection and offer
// 撤销.

import Foundation
import OpenTodoData
import OpenTodoDomain

extension AppModel {
    /// The tasks of `view` as shown, top to bottom, leaving out folded
    /// groups: the order Shift-clicks and 全选 go by.
    public func shownOrder(in view: ViewRef) -> [String] {
        sections(for: view).filter { !taskList.isFolded($0, in: view) || $0.title == nil }.flatMap { $0.tasks.map(\.id) }
    }

    /// Whether `view` lets tasks be picked together (not the trash).
    public func canPick(in view: ViewRef) -> Bool { view != .smart(.trash) }

    /// The picked tasks for the batch views; nil when nothing is picked.
    public var batchSelection: BatchSelection? {
        guard selection.isActive else { return nil }
        return BatchSelection(ids: selection.ids, tasks: data.tasks.filter { selection.contains($0.id) })
    }

    /// Runs what the batch panel or bar reported.
    public func performBatch(_ action: BatchAction) async {
        let repo = self.repo
        switch action {
        case .setDue(let changes):
            await attempt { for c in changes { try await repo.setDue(c.id, c.date, c.time) } }
        case .setPriority(let ids, let p):
            await attempt { for id in ids { try await repo.setPriority(id, p) } }
        case .moveToList(let ids, let listId):
            await attempt { for id in ids { try await repo.moveToList(id, listId) } }
        case .setTags(let changes):
            await attempt { for c in changes { try await repo.setTags(c.id, c.tags) } }
        case .setPinned(let ids, let pinned):
            await attempt { for id in ids { try await repo.setPinned(id, pinned) } }
        case .complete(let ids):
            var repeats: [RepeatCompletion] = []
            var plain: [String] = []
            await attempt {
                for id in ids {
                    if let r = try await repo.setCompleted(id, true) { repeats.append(r) } else { plain.append(id) }
                }
            }
            selection.clear()
            let r = repeats, p = plain
            notices.show("已完成 \(ids.count) 个任务", undoName: "完成") {
                for c in r { try? await repo.undoRepeatCompletion(c) }
                for id in p { _ = try? await repo.setCompleted(id, false) }
            }
        case .trash(let ids):
            await attempt { for id in ids { try await repo.trashTask(id) } }
            selection.clear()
            if let open = selectedTaskId, ids.contains(open) { closeTask() }
            notices.show("已把 \(ids.count) 个任务移到垃圾桶", undoName: "删除") {
                for id in ids { try? await repo.restoreTask(id) }
            }
        case .copiedTitles(let count):
            notices.show("已复制 \(count) 个任务的标题")
        case .clearSelection:
            selection.clear()
        case .selectAll:
            selection.selectAll(shownOrder(in: view))
        }
    }
}
