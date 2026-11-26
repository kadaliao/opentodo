// `-OTOpen batch:<state>` (debug builds): the batch actions over the demo
// data's 工作 list with four tasks picked, for screenshots.
//
//     batch:panel   the wide window's panel beside the list
//     batch:bar     the bar under the list (iOS: the bottom toolbar)
//     batch:tags    the panel with the tag editor open

import Foundation
import OpenTodoData
import OpenTodoDomain
import SwiftUI

enum BatchDebugState: String, CaseIterable {
    case panel, bar, tags
}

struct BatchDebugPresenter: ViewModifier {
    let route: DebugRoute?

    private var state: BatchDebugState? {
        if case .batch(let s) = route { BatchDebugState(rawValue: s) } else { nil }
    }

    func body(content: Content) -> some View {
        if let state {
            content.overlay { BatchDebugScreen(state: state) }
        } else {
            content
        }
    }
}

private struct BatchDebugScreen: View {
    let state: BatchDebugState
    let today = Day.today()
    let data: TaskData
    @State private var picked: Set<String> = ["report", "review", "invoice", "slides"]

    init(state: BatchDebugState) {
        self.state = state
        data = DemoData.make(today: today, now: .now())
    }

    private var snapshot: Bool { ProcessInfo.processInfo.arguments.contains("-OTSnapshot") }

    private var listTasks: [TodoTask] { data.tasks.filter { $0.listId == "work" && $0.trashedAt == nil } }
    private var tags: [String] { Array(Set(data.tasks.flatMap(\.tags))).sorted() }
    private var selection: BatchSelection { BatchSelection(ids: picked, tasks: data.tasks) }

    private func perform(_ action: BatchAction) {
        print("batch: \(action)")
        switch action {
        case .clearSelection, .complete, .trash: picked = []
        case .selectAll: picked = Set(listTasks.map(\.id))
        default: break
        }
    }

    private var list: some View {
        List(selection: $picked) {
            ForEach(listTasks) { t in
                TaskRow(t, now: .now()).tag(t.id)
            }
        }
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
    }

    private var panel: some View {
        BatchPanel(context: BatchContext(selection: selection, lists: data.lists, knownTags: tags, today: today,
                                         onAction: perform),
                   editingTags: state == .tags && !snapshot)
    }

    var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                list
                if state == .bar && !picked.isEmpty {
                    BatchBar(selection: selection, lists: data.lists, knownTags: tags, today: today, onAction: perform)
                }
            }
            if state != .bar {
                Divider()
                Group {
                    if picked.isEmpty { Color.clear } else { panel }
                }
                .frame(width: 380)
            }
        }
        .background(.background)
        .overlay(alignment: .topTrailing) {
            // -OTSnapshot draws only the main window: the tag editor's
            // popover goes in the window instead.
            if state == .tags && snapshot {
                BatchTagsView(BatchTagsEditor(tasks: selection.tasks, known: tags)) { _ in }
                    .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
                    .padding(.top, 150)
                    .padding(.trailing, 60)
            }
        }
        // -OTSnapshot can't draw scroll views that scroll: show them still.
        .scrollDisabled(snapshot)
        #else
        NavigationStack {
            Group {
                if state == .bar {
                    list.batchBottomBar(selection: picked.isEmpty ? nil : selection, lists: data.lists,
                                        knownTags: tags, today: today, onAction: perform)
                } else {
                    panel
                }
            }
            .navigationTitle("💼 工作")
            .navigationBarTitleDisplayMode(.inline)
        }
        #endif
    }
}
