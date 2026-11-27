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

/// A one-line prompt: 添加分组, 重命名分组, 添加标签. With suggestions (the
/// tags in use) they're listed under the field, narrowed as it's typed;
/// a click picks one, and so do ↓ / ↑ then Return.
private struct TextPromptSheet: View {
    @Environment(\.uiScale) private var s
    let request: TextPromptRequest
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    /// The suggestion ↓ / ↑ moved to; Return picks it.
    @State private var highlighted: Int?
    @FocusState private var focused: Bool

    /// At most this many show: typing narrows them.
    private static let shown = 8

    private var matches: [String] {
        Array(tagSuggestions(request.suggestions, typed: text).prefix(Self.shown))
    }

    var body: some View {
        NavigationStack {
            Form {
                // macOS puts a form field's title beside it and leaves the
                // field blank; hidden, the field takes the row and shows
                // the placeholder.
                TextField(request.placeholder, text: $text, prompt: Text(request.placeholder))
                    .labelsHidden()
                    .focused($focused)
                    .onSubmit { submit(highlighted.flatMap { matches.indices.contains($0) ? matches[$0] : nil } ?? text) }
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.upArrow) { move(-1) }
                if !request.suggestions.isEmpty { suggestionsSection }
            }
            .formStyle(.grouped)
            .navigationTitle(request.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(request.action) { submit(text) }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 360 * s, minHeight: (request.suggestions.isEmpty ? 150 : 340) * s)
        .presentationDetents(request.suggestions.isEmpty ? [.height(220)] : [.medium, .large])
        .defaultFocus($focused, true)
        .onAppear {
            text = request.initial
            focused = true
        }
        .onChange(of: text) { highlighted = nil }
    }

    @ViewBuilder private var suggestionsSection: some View {
        let matches = matches
        Section {
            ForEach(Array(matches.enumerated()), id: \.element) { i, tag in
                Button {
                    submit(tag)
                } label: {
                    Label(tag, systemImage: "number")
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("添加这个标签")
                .listRowBackground(i == highlighted ? Color.accentColor.opacity(0.15) : nil)
            }
        } header: {
            Text(text.trimmingCharacters(in: .whitespaces).isEmpty ? "已有标签" : "匹配的标签")
                .uiDefaultFont(.headline)
        } footer: {
            if matches.isEmpty {
                Text("没有匹配的标签，按回车新建“\(text.trimmingCharacters(in: .whitespaces))”。")
                    .uiDefaultFont(.subheadline)
            }
        }
    }

    /// ↓ / ↑: the next or previous suggestion; up from the first goes back
    /// to the field's own text.
    private func move(_ by: Int) -> KeyPress.Result {
        let count = matches.count
        guard count > 0 else { return .ignored }
        switch (highlighted, by > 0) {
        case (nil, true): highlighted = 0
        case (nil, false): return .ignored
        case (let i?, true): highlighted = min(i + 1, count - 1)
        case (let i?, false): highlighted = i > 0 ? i - 1 : nil
        }
        return .handled
    }

    private func submit(_ value: String) {
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        dismiss()
        request.onSubmit(value)
    }
}

/// 添加清单 / 编辑清单: a name and an emoji (the Flutter version's choices).
private struct ListEditorSheet: View {
    @Environment(\.uiScale) private var s
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
                    // Hidden label: the field takes the row (TextPromptSheet).
                    TextField("清单名称", text: $name, prompt: Text("清单名称"))
                        .labelsHidden()
                        .focused($focused)
                        .onSubmit(submit)
                }
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6 * s), count: 6), spacing: 6 * s) {
                        ForEach(Self.emojis, id: \.self) { e in
                            Button {
                                emoji = e
                            } label: {
                                Text(e)
                                    .uiFont(.title2)
                                    .frame(maxWidth: .infinity, minHeight: 40 * s)
                                    .background(emoji == e ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.clear),
                                                in: RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(e)
                            .accessibilityAddTraits(emoji == e ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4 * s)
                } header: {
                    Text("图标").uiDefaultFont(.headline)
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
        .frame(minWidth: 380 * s, minHeight: 330 * s)
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
