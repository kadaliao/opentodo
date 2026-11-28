// 添加清单 / 编辑清单: the name, the icon and the colour (`model.present.listEditor`,
// shown by DialogHost).
//
// The icon is a system symbol (drawn in the list's colour), an emoji, or
// one typed in — any emoji, or a character or two (`ListIcon.custom`); each
// kind is a tab, the first two by category (`ListIconCatalog`). The colour
// also tints the default icon when there's none.

import OpenTodoDomain
import SwiftUI

struct ListEditorSheet: View {
    @Environment(\.uiScale) private var s
    let request: ListEditorRequest
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon: ListIcon? = .emoji("📋")
    @State private var color: Int?
    @State private var tab: Tab = .emoji
    @State private var symbolCategory = ListIconCatalog.symbols[0].name
    @State private var emojiCategory = ListIconCatalog.emoji[0].name
    @State private var typed = ""
    @FocusState private var focused: Bool

    enum Tab: String, Hashable { case symbol, emoji, custom }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12 * s) {
                        ListIconPreview(icon: icon, color: color, size: 40)
                        // Hidden label: the field takes the row (TextPromptSheet).
                        TextField("清单名称", text: $name, prompt: Text("清单名称"))
                            .labelsHidden()
                            .focused($focused)
                            .onSubmit(submit)
                    }
                }
                Section {
                    Picker("图标", selection: $tab) {
                        Text("符号").tag(Tab.symbol)
                        Text("Emoji").tag(Tab.emoji)
                        Text("自定义").tag(Tab.custom)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    switch tab {
                    case .symbol:
                        CategoryChips(categories: ListIconCatalog.symbols, selection: $symbolCategory)
                        iconGrid(ListIconCatalog.symbols, symbolCategory) { .symbol($0) }
                    case .emoji:
                        CategoryChips(categories: ListIconCatalog.emoji, selection: $emojiCategory)
                        iconGrid(ListIconCatalog.emoji, emojiCategory) { .emoji($0) }
                    case .custom:
                        customRow
                    }
                } header: {
                    HStack {
                        Text("图标")
                        Spacer()
                        if icon != nil {
                            Button("不用图标") { icon = nil }
                                .buttonStyle(.borderless)
                                .uiFont(.caption)
                        }
                    }
                    .uiDefaultFont(.headline)
                }
                Section {
                    ColorDotsPicker(color: $color)
                } header: {
                    HStack {
                        Text("颜色")
                        Spacer()
                        if color != nil {
                            Button("默认") { color = nil }
                                .buttonStyle(.borderless)
                                .uiFont(.caption)
                        }
                    }
                    .uiDefaultFont(.headline)
                } footer: {
                    Text("符号图标和没有图标时的默认图标用这个颜色。").uiFont(.caption).foregroundStyle(.secondary)
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
        .frame(minWidth: 440 * s, minHeight: 560 * s)
        .presentationDetents([.large])
        .onAppear {
            if let list = request.list {
                name = list.name
                icon = list.icon
                color = list.color
            }
            switch icon {
            case .symbol(let n)?:
                tab = .symbol
                if let c = ListIconCatalog.symbols.first(where: { $0.items.contains(n) }) { symbolCategory = c.name }
            case .emoji(let e)?:
                if let c = ListIconCatalog.emoji.first(where: { $0.items.contains(e) }) {
                    emojiCategory = c.name
                } else {
                    tab = .custom
                    typed = e
                }
            case nil:
                break
            }
            if let t = request.tab { tab = t }
            focused = request.list == nil
        }
    }

    private func iconGrid(_ categories: [ListIconCategory], _ selected: String,
                          make: @escaping (String) -> ListIcon) -> some View {
        let items = categories.first { $0.name == selected }?.items ?? []
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 40 * s), spacing: 6 * s)], spacing: 6 * s) {
            ForEach(items, id: \.self) { item in
                let value = make(item)
                Button {
                    icon = value
                } label: {
                    ListIconGlyph(icon: value, color: color, size: 26)
                        .frame(maxWidth: .infinity, minHeight: 40 * s)
                        .background(icon == value ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 8 * s, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item)
                .accessibilityAddTraits(icon == value ? .isSelected : [])
            }
        }
        .padding(.vertical, 4 * s)
    }

    @ViewBuilder private var customRow: some View {
        HStack(spacing: 8 * s) {
            TextField("自定义图标", text: $typed, prompt: Text("输入一个 emoji，或一两个字"))
                .labelsHidden()
                .onSubmit(takeTyped)
                .onChange(of: typed) { takeTyped() }
            if let custom = ListIcon.custom(typed) {
                ListIconGlyph(icon: custom, color: color, size: 22)
            }
        }
        #if os(macOS)
        Text("按 ⌃⌘空格 可以打开表情与符号，挑一个放进来。")
            .uiFont(.caption)
            .foregroundStyle(.secondary)
        #endif
    }

    private func takeTyped() {
        if let custom = ListIcon.custom(typed) { icon = custom }
    }

    private func submit() {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        dismiss()
        let stored = icon?.stored
        if let list = request.list {
            let color = color
            model.run { try await model.repo.updateList(list.id, name: name, emoji: .some(stored), color: .some(color)) }
        } else {
            model.run { await model.addList(name: name, emoji: stored, color: color) }
        }
    }
}

/// The categories of a tab, a row of chips that scrolls sideways.
private struct CategoryChips: View {
    @Environment(\.uiScale) private var s
    let categories: [ListIconCategory]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6 * s) {
                ForEach(categories) { c in
                    let on = c.name == selection
                    Button {
                        selection = c.name
                    } label: {
                        Text(c.name)
                            .uiFont(.callout, weight: on ? .semibold : .regular)
                            .padding(.horizontal, 10 * s)
                            .padding(.vertical, 4 * s)
                            .background(on ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.6)),
                                        in: Capsule())
                            .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

/// An icon by itself, `size` points at 标准: a symbol in the list's
/// colour, an emoji or a typed-in character or two as text.
struct ListIconGlyph: View {
    @Environment(\.uiScale) private var s
    var icon: ListIcon
    var color: Int?
    var size: CGFloat

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.8 * s, weight: .medium))
                .foregroundStyle(Palette.list(color))
        case .emoji(let e):
            Text(e)
                .font(.system(size: (e.count > 1 ? size * 0.6 : size) * s, weight: e.count > 1 ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

/// The icon as the list will have it, on a tinted circle.
private struct ListIconPreview: View {
    @Environment(\.uiScale) private var s
    var icon: ListIcon?
    var color: Int?
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Palette.list(color).opacity(0.16))
            ListIconGlyph(icon: icon ?? .symbol(ViewSymbol.list), color: color, size: size * 0.55)
        }
        .frame(width: size * s, height: size * s)
        .accessibilityHidden(true)
    }
}
