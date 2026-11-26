// 全部习惯: every habit, active and archived, to edit, archive, bring back
// or delete. A sheet from the habits page.

import OpenTodoDomain
import SwiftUI

struct HabitListView: View {
    @Environment(\.uiScale) private var s
    var habits: [Habit]
    var today: Day
    var onSaveHabit: (Habit) -> Void
    var newId: () -> String
    var clock: () -> Int

    @Environment(\.dismiss) private var dismiss
    @State private var editor: HabitEditorTarget?
    @State private var deleting: Habit?

    private var active: [Habit] { sorted(habits.filter { $0.archivedAt == nil }) }
    private var archived: [Habit] { sorted(habits.filter { $0.archivedAt != nil }) }

    private func sorted(_ hs: [Habit]) -> [Habit] {
        hs.sorted { a, b in a.sortOrder != b.sortOrder ? a.sortOrder < b.sortOrder : a.id < b.id }
    }

    var body: some View {
        NavigationStack {
            List {
                if habits.isEmpty {
                    ContentUnavailableView("还没有习惯", systemImage: "leaf", description: Text("点右上角的加号新建一个。"))
                }
                if !active.isEmpty {
                    Section { ForEach(active, content: row) } header: {
                        Text("进行中").uiDefaultFont(.subheadline, weight: .semibold)
                    }
                }
                if !archived.isEmpty {
                    Section { ForEach(archived, content: row) } header: {
                        Text("已归档").uiDefaultFont(.subheadline, weight: .semibold)
                    }
                }
            }
            .navigationTitle("全部习惯")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("新建习惯", systemImage: "plus") { editor = HabitEditorTarget(habitId: nil) }
                }
            }
            .sheet(item: $editor) { target in
                HabitEditorView(habit: target.habitId.flatMap { id in habits.first { $0.id == id } }, today: today) { draft, base in
                    onSaveHabit(draft.habit(base: base, newId: newId(), now: clock()))
                }
            }
            .confirmationDialog(
                "删除“\(deleting?.name ?? "")”？",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible,
                presenting: deleting
            ) { h in
                Button("删除习惯和打卡记录", role: .destructive) { onSaveHabit(deletedHabit(h, now: clock())) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380 * s, minHeight: 440 * s)
        #endif
    }

    private func row(_ h: Habit) -> some View {
        Button {
            editor = HabitEditorTarget(habitId: h.id)
        } label: {
            HStack(spacing: 12 * s) {
                EmojiBadge(emoji: h.emoji, color: h.color, fallback: "leaf.fill", size: 34)
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(h.name).foregroundStyle(h.archivedAt == nil ? .primary : .secondary)
                    Text("\(frequencyText(h.frequency)) · \(goalText(h)) · \(h.section.name)")
                        .uiFont(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("删除", systemImage: "trash", role: .destructive) { deleting = h }
            archiveButton(h).tint(.indigo)
        }
        .contextMenu {
            Button("编辑", systemImage: "pencil") { editor = HabitEditorTarget(habitId: h.id) }
            archiveButton(h)
            Divider()
            Button("删除", systemImage: "trash", role: .destructive) { deleting = h }
        }
    }

    private func archiveButton(_ h: Habit) -> some View {
        Button(h.archivedAt == nil ? "归档" : "恢复", systemImage: h.archivedAt == nil ? "archivebox" : "arrow.uturn.backward") {
            var x = h
            x.archivedAt = h.archivedAt == nil ? clock() : nil
            x.updatedAt = clock()
            x.dirty = true
            onSaveHabit(x)
        }
    }
}
