// Adding, renaming, moving and deleting a list's sections (分组), ported
// from `app/lib/ui/section_actions.dart`: the ⋯ menu of a section header
// or board column, and the dialogs it opens. The list uses the same pieces
// (`horizontal: false` says 上移 / 下移 instead of 左移 / 右移).
//
//     @State var dialog: SectionDialog?
//     Menu { SectionMenu(section: s, among: sections, dialog: $dialog, perform: act) } label: { … }
//     …
//     .sectionDialogs($dialog, perform: act)

import OpenTodoDomain
import SwiftUI

/// What the person did to a list's sections, for whoever writes it.
public enum SectionAction: Hashable, Sendable {
    /// `TaskRepo.addSection(listId, name)`: at the end.
    case add(listId: String, name: String)
    /// `TaskRepo.updateSection(id, name:)`.
    case rename(sectionId: String, name: String)
    /// `TaskRepo.updateSection(id, sortOrder:)` for each.
    case reorder([String: Double])
    /// `TaskRepo.deleteSection(id)`: its tasks stay in the list, under 未分组.
    case delete(sectionId: String)
}

/// A dialog about a section that's up.
public enum SectionDialog: Hashable, Sendable, Identifiable {
    case add(listId: String)
    case rename(ListSection)
    case delete(ListSection)

    public var id: String {
        switch self {
        case .add(let listId): "add-\(listId)"
        case .rename(let s): "rename-\(s.id)"
        case .delete(let s): "delete-\(s.id)"
        }
    }
}

/// The entries of a section's ⋯ menu.
public enum SectionMenuEntry: Hashable, Sendable {
    case rename, back, forward, delete

    public func label(horizontal: Bool) -> String {
        switch self {
        case .rename: "重命名"
        case .back: horizontal ? "左移" : "上移"
        case .forward: horizontal ? "右移" : "下移"
        case .delete: "删除分组"
        }
    }

    public func symbol(horizontal: Bool) -> String {
        switch self {
        case .rename: "pencil"
        case .back: horizontal ? "arrow.left" : "arrow.up"
        case .forward: horizontal ? "arrow.right" : "arrow.down"
        case .delete: "trash"
        }
    }

    /// What the section at `index` of `count` offers: moving back unless it
    /// is first, forward unless it is last.
    public static func entries(index: Int?, count: Int) -> [SectionMenuEntry] {
        var out: [SectionMenuEntry] = [.rename]
        if let index, index > 0 { out.append(.back) }
        if let index, index < count - 1 { out.append(.forward) }
        out.append(.delete)
        return out
    }
}

/// A name typed into a section dialog, as saved: trimmed; nil when empty.
public func sectionName(_ text: String) -> String? {
    let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
}

/// The ⋯ menu's items for `section`, `among` its list's sections in order.
/// Renaming and deleting open `dialog`; moving goes straight to `perform`.
public struct SectionMenu: View {
    let section: ListSection
    let among: [ListSection]
    let horizontal: Bool
    @Binding var dialog: SectionDialog?
    let perform: (SectionAction) -> Void

    public init(
        section: ListSection,
        among: [ListSection],
        horizontal: Bool = false,
        dialog: Binding<SectionDialog?>,
        perform: @escaping (SectionAction) -> Void
    ) {
        self.section = section
        self.among = among
        self.horizontal = horizontal
        _dialog = dialog
        self.perform = perform
    }

    public var body: some View {
        let entries = SectionMenuEntry.entries(index: among.firstIndex { $0.id == section.id }, count: among.count)
        ForEach(entries, id: \.self) { entry in
            if entry == .delete { Divider() }
            Button(role: entry == .delete ? .destructive : nil) {
                run(entry)
            } label: {
                Label(entry.label(horizontal: horizontal), systemImage: entry.symbol(horizontal: horizontal))
            }
        }
    }

    private func run(_ entry: SectionMenuEntry) {
        switch entry {
        case .rename: dialog = .rename(section)
        case .delete: dialog = .delete(section)
        case .back, .forward:
            let orders = planSectionShift(among, section.id, by: entry == .back ? -1 : 1)
            if !orders.isEmpty { perform(.reorder(orders)) }
        }
    }
}

extension View {
    /// Shows the section dialogs: a name for a new section or a new name,
    /// and the question before deleting one.
    public func sectionDialogs(_ dialog: Binding<SectionDialog?>, perform: @escaping (SectionAction) -> Void) -> some View {
        modifier(SectionDialogs(dialog: dialog, perform: perform))
    }
}

private struct SectionDialogs: ViewModifier {
    @Binding var dialog: SectionDialog?
    let perform: (SectionAction) -> Void
    @State private var name = ""

    private var naming: Binding<Bool> {
        Binding {
            switch dialog {
            case .add?, .rename?: true
            default: false
            }
        } set: { if !$0 { dialog = nil } }
    }

    private var deleting: Binding<Bool> {
        Binding {
            if case .delete? = dialog { true } else { false }
        } set: { if !$0 { dialog = nil } }
    }

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: naming, presenting: dialog) { d in
                TextField(placeholder, text: $name)
                Button("取消", role: .cancel) {}
                Button("保存") { save(d) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sectionName(name) == nil)
            }
            .alert(deleteTitle, isPresented: deleting, presenting: dialog) { d in
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if case .delete(let s) = d { perform(.delete(sectionId: s.id)) }
                }
            } message: { _ in
                Text("分组里的任务会留在清单里，归到“未分组”。")
            }
            .onChange(of: dialog, initial: true) { _, d in
                if case .rename(let s)? = d { name = s.name } else { name = "" }
            }
    }

    private var title: String {
        if case .rename? = dialog { "重命名分组" } else { "添加分组" }
    }

    private var placeholder: String {
        if case .add? = dialog { "分组名称，比如“进行中”" } else { "名称" }
    }

    private var deleteTitle: String {
        if case .delete(let s)? = dialog { "删除分组“\(s.name)”？" } else { "" }
    }

    private func save(_ d: SectionDialog) {
        guard let name = sectionName(name) else { return }
        switch d {
        case .add(let listId): perform(.add(listId: listId, name: name))
        case .rename(let s): perform(.rename(sectionId: s.id, name: name))
        case .delete: break
        }
    }
}
