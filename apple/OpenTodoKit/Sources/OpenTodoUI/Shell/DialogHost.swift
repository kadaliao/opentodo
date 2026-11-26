// Shows the dialogs `AppModel.present` asks for, once per window: 确定 /
// 取消 questions, one-line prompts, the list editor, the date dialog
// opened from a menu, the filter editor, the settings sheet (iOS) and the
// quick-add sheet (iPhone). Each request is one modifier here; a feature
// that brings its own dialog replaces its line (the filter editor's is
// `FilterEditorSheet`, Filters/FilterActions.swift).

import OpenTodoData
import OpenTodoDomain
import SwiftUI

struct DialogHost: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var present = model.present
        content
            .confirmationDialog(present.confirm?.title ?? "", isPresented: isPresented($present.confirm),
                                titleVisibility: .visible, presenting: present.confirm) { request in
                Button(request.action, role: request.destructive ? .destructive : nil) { request.onConfirm() }
                Button("取消", role: .cancel) {}
            } message: { request in
                if let message = request.message { Text(message) }
            }
            .sheet(item: $present.textPrompt) { TextPromptSheet(request: $0) }
            .sheet(item: $present.listEditor) { ListEditorSheet(request: $0) }
            .sheet(item: $present.schedule) { request in
                if let task = model.task(request.taskId) {
                    ScheduleEditorView(
                        ScheduleDraft(task: task), defaults: model.settings.settings.defaults,
                        notificationsAllowed: model.notificationsAllowed,
                        openNotificationSettings: model.openNotificationSettings,
                        onCommit: { draft in
                            present.schedule = nil
                            model.run { await model.setSchedule(task.id, draft) }
                        },
                        onCancel: { present.schedule = nil })
                    .modifier(ScheduleSheetStyle())
                } else {
                    // Deleted elsewhere while the sheet was opening.
                    Color.clear.onAppear { present.schedule = nil }
                }
            }
            .sheet(item: $present.filterEditor) { FilterEditorSheet(request: $0) }
            .sheet(isPresented: $present.quickAdd) { QuickAddSheet() }
            #if os(iOS)
            .sheet(isPresented: $present.settings) { SettingsSheet() }
            #endif
    }

    private func isPresented<T>(_ item: Binding<T?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}

/// A one-line prompt: 添加分组, 重命名分组, 添加标签.
private struct TextPromptSheet: View {
    let request: TextPromptRequest
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(request.placeholder, text: $text)
                    .focused($focused)
                    .onSubmit(submit)
            }
            .formStyle(.grouped)
            .navigationTitle(request.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(request.action, action: submit)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 150)
        .presentationDetents([.height(220)])
        .onAppear {
            text = request.initial
            focused = true
        }
    }

    private func submit() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        dismiss()
        request.onSubmit(text)
    }
}

/// 添加清单 / 编辑清单: a name and an emoji (the Flutter version's choices).
private struct ListEditorSheet: View {
    let request: ListEditorRequest
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji: String? = ListEditorSheet.emojis[0]
    @FocusState private var focused: Bool

    static let emojis = ["📋", "💼", "🏠", "📚", "🏃", "🛒", "✈️", "💡", "🎯", "❤️", "🎨", "💰"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("清单名称", text: $name)
                        .focused($focused)
                        .onSubmit(submit)
                }
                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                        ForEach(Self.emojis, id: \.self) { e in
                            Button {
                                emoji = e
                            } label: {
                                Text(e)
                                    .font(.title2)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(emoji == e ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.clear),
                                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(e)
                            .accessibilityAddTraits(emoji == e ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(request.list == nil ? "添加清单" : "编辑清单")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(request.list == nil ? "添加" : "完成", action: submit)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 330)
        .presentationDetents([.medium])
        .onAppear {
            if let list = request.list {
                name = list.name
                emoji = list.emoji
            }
            focused = true
        }
    }

    private func submit() {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        dismiss()
        if let list = request.list {
            model.run { try await model.repo.updateList(list.id, name: name, emoji: emoji) }
        } else {
            model.run { await model.addList(name: name, emoji: emoji) }
        }
    }
}
