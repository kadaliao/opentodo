// The filter editor and filter ordering wired into the app (`AppModel`):
// `DialogHost` shows `FilterEditorSheet` for `model.present.filterEditor`
// (asked for by `model.editFilter(_:)`), the sidebar's drag calls
// `moveFilter`. Deleting is `model.askDeleteFilter(_:)` (AppModel+Actions).

import OpenTodoDomain
import SwiftUI

extension AppModel {
    /// Saves what the editor gave back: a new filter is added and shown
    /// (as the Dart version selects it), an existing one is updated.
    public func saveFilter(_ request: FilterEditorRequest, _ result: FilterEditorResult) async {
        await attempt {
            if let filter = request.filter {
                try await repo.updateFilter(filter.id, name: result.name, rule: result.rule.encode())
            } else {
                let id = try await repo.addFilter(result.name, result.rule.encode())
                select(.filter(id))
            }
        }
    }

    /// Puts the filter at `index` of the sidebar's filters (counting it
    /// where it is now), as dragging it there does.
    public func moveFilter(_ id: String, to index: Int) async {
        let orders = planFilterMove(filters, moving: id, to: index)
        guard !orders.isEmpty else { return }
        await attempt {
            for (filterId, order) in orders { try await repo.updateFilter(filterId, sortOrder: order) }
        }
    }
}

/// The filter editor as `DialogHost` shows it, on the window's data.
struct FilterEditorSheet: View {
    let request: FilterEditorRequest
    @Environment(AppModel.self) private var model

    var body: some View {
        FilterEditor(
            filter: request.filter, lists: model.lists, tags: model.tags, tasks: model.data.tasks, now: model.now,
            onSave: { result in model.run { await model.saveFilter(request, result) } }
        )
    }
}
