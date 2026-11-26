// The rule part of the filter editor, on its own, for anything that edits
// a `FilterRule` without it being a saved filter: 四象限's quadrants
// (efficiency), filtering the calendar (time).
//
// Inside a Form section (one row that opens the editor in a sheet):
//
//     Section {
//         TextField("名称", text: $name)
//         FilterRuleRow(rule: $rule, lists: model.lists, tags: model.tags, today: model.today)
//     }
//
// As the sections of a Form of your own (普通 / 高级 switch, then the rows):
//
//     Form {
//         FilterRuleEditor(rule: $rule, lists: lists, tags: tags, today: today,
//                          footer: "现在有 3 个未完成任务符合条件")
//     }
//     .formStyle(.grouped)
//
// The binding gets the rule as it would be saved (rows with nothing chosen
// left out, keyword text trimmed) on every change; store it with
// `rule.encode()`. Setting the binding from outside (恢复默认) starts the
// editor afresh. `lists` are the person's lists (deleted ones are ignored;
// a deleted list still in the rule shows as 已删除的清单), `tags` every tag
// in use, `today` for the custom date range.
//
// For MatrixRootView's slot:
//
//     ruleEditor: { rule in AnyView(FilterRuleRow(rule: rule, lists: …, tags: …, today: …)) }

import OpenTodoDomain
import SwiftUI

public struct FilterRuleEditor: View {
    @Binding var rule: FilterRule
    let context: FilterPickerContext
    let footer: String?

    @State private var model: FilterEditorModel
    /// What this editor last handed out, to tell its own changes from ones
    /// made outside.
    @State private var written: FilterRule

    public init(rule: Binding<FilterRule>, lists: [TaskList], tags: [String], today: Day, footer: String? = nil) {
        _rule = rule
        context = FilterPickerContext(lists: lists, tags: tags, today: today)
        self.footer = footer
        _model = State(initialValue: FilterEditorModel(rule: rule.wrappedValue))
        _written = State(initialValue: rule.wrappedValue)
    }

    public var body: some View {
        Section {
            FilterModePicker(model: $model)
        }
        FilterRuleSections(model: $model, context: context, footer: footer)
            .onChange(of: model.rule) {
                let saved = model.savedRule
                written = saved
                if rule != saved { rule = saved }
            }
            .onChange(of: rule) { _, new in
                if new != written {
                    model = FilterEditorModel(rule: new)
                    written = new
                }
            }
    }
}

/// One row (筛选条件 and a summary of the rule) that opens `FilterRuleEditor`
/// in a sheet with 完成.
public struct FilterRuleRow: View {
    @Binding var rule: FilterRule
    let lists: [TaskList]
    let tags: [String]
    let today: Day
    let title: String

    @State private var editing = false

    public init(rule: Binding<FilterRule>, lists: [TaskList], tags: [String], today: Day, title: String = "筛选条件") {
        _rule = rule
        self.lists = lists
        self.tags = tags
        self.today = today
        self.title = title
    }

    public var body: some View {
        Button {
            editing = true
        } label: {
            LabeledContent(title) {
                HStack(spacing: 4) {
                    Text(filterRuleSummary(rule, lists: lists, today: today))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $editing) {
            NavigationStack {
                Form {
                    FilterRuleEditor(rule: $rule, lists: lists, tags: tags, today: today)
                }
                .formStyle(.grouped)
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { editing = false }
                    }
                }
            }
            #if os(macOS)
            .frame(width: 540, height: 480)
            #endif
        }
    }
}

/// A short description of a rule: 所有任务, or the conditions joined with
/// ；(且) or “或”, e.g. 清单：工作；优先级：不包含 高.
public func filterRuleSummary(_ rule: FilterRule, lists: [TaskList], today: Day? = nil) -> String {
    let byId = Dictionary(lists.filter { $0.deletedAt == nil }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let parts = rule.tidy().conditions.map { c -> String in
        guard let field = c.field else { return "新版本加的条件" }
        return "\(field.label)：\(c.exclude ? "不包含 " : "")\(describeValues(field, c.values, lists: byId, today: today))"
    }
    if parts.isEmpty { return "所有任务" }
    return parts.joined(separator: rule.matchAll ? "；" : " 或 ")
}

/// 普通 / 高级; 普通 greyed out when the rule needs 高级.
struct FilterModePicker: View {
    @Binding var model: FilterEditorModel

    var body: some View {
        Picker("方式", selection: Binding(get: { model.advanced }, set: { model.setAdvanced($0) })) {
            Text("普通").tag(false)
                .selectionDisabled(!model.canSimple)
            Text("高级").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .help(model.canSimple ? "" : "这些条件只能在“高级”里编辑")
    }
}

/// The 普通 or 高级 rows of a rule, as Form sections.
struct FilterRuleSections: View {
    @Binding var model: FilterEditorModel
    let context: FilterPickerContext
    let footer: String?

    var body: some View {
        if model.advanced {
            advancedForm
        } else {
            simpleForm
        }
    }

    // MARK: 普通

    @ViewBuilder private var simpleForm: some View {
        Section {
            ForEach([FilterField.list, .tag, .date], id: \.self) { f in
                FilterValuePicker(
                    field: f,
                    values: Binding(get: { model.simpleValues(f) }, set: { model.setSimpleValues(f, $0) }),
                    context: context,
                    label: f.label
                )
            }
            LabeledContent("优先级") { priorityChips }
            let keyword = TextField("内容包含", text: Binding(get: { model.simpleKeyword }, set: { model.setSimpleKeyword($0) }), prompt: Text("标题或描述里的文字"))
            #if os(iOS)
            LabeledContent("内容包含") { keyword.multilineTextAlignment(.trailing) }
            #else
            keyword
            #endif
        } footer: {
            countFooter
        }
    }

    private var priorityChips: some View {
        let chosen = model.simpleValues(.priority)
        return HStack(spacing: 6) {
            PriorityChip(label: "所有", on: chosen.isEmpty) { model.setSimpleValues(.priority, []) }
            ForEach(priorityChoices, id: \.key) { p in
                let on = chosen.contains(p.key)
                PriorityChip(label: p.label, on: on) { model.setPriority(p.key, on: !on) }
            }
        }
    }

    @ViewBuilder private var countFooter: some View {
        if let footer { Text(footer) }
    }

    // MARK: 高级

    @ViewBuilder private var advancedForm: some View {
        Section {
            Picker("满足", selection: Binding(get: { model.rule.matchAll }, set: { model.setMatchAll($0) })) {
                Text("全部条件").tag(true)
                Text("任一条件").tag(false)
            }
        }
        let rows = Array(zip(model.rowKeys, model.rule.conditions).enumerated())
        ForEach(rows, id: \.element.0) { i, row in
            Section {
                conditionRow(i, row.1)
            }
        }
        Section {
            Button {
                withAnimation { model.addCondition() }
            } label: {
                Label("添加条件", systemImage: "plus")
            }
            #if os(macOS)
            .buttonStyle(.borderless)
            #endif
        } footer: {
            countFooter
        }
    }

    @ViewBuilder
    private func conditionRow(_ i: Int, _ c: FilterCondition) -> some View {
        let remove = Button(role: .destructive) {
            withAnimation { model.removeCondition(at: i) }
        } label: {
            Image(systemName: "minus.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
        }
        .buttonStyle(.borderless)
        .help("删除条件")
        .accessibilityLabel("删除条件")

        if let field = c.field {
            let fieldPicker = Picker("条件", selection: Binding(get: { field }, set: { model.setField(at: i, $0) })) {
                ForEach(FilterField.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            #if os(iOS)
            // In a row of their own on a phone they read as plain grey
            // text; tinted they look like the menus they are.
            .tint(.accentColor)
            #endif
            let opPicker = Picker("关系", selection: Binding(get: { c.exclude }, set: { model.setExclude(at: i, $0) })) {
                Text("包含").tag(false)
                Text("不包含").tag(true)
            }
            .labelsHidden()
            .fixedSize()
            #if os(iOS)
            .tint(.accentColor)
            #endif
            #if os(macOS)
            HStack(spacing: 10) {
                fieldPicker
                opPicker
                valueControl(i, c, field)
                    .frame(maxWidth: .infinity)
                remove
            }
            #else
            HStack(spacing: 4) {
                fieldPicker
                opPicker
                Spacer()
                remove
            }
            valueControl(i, c, field)
            #endif
        } else {
            HStack {
                Text("新版本加的条件，这个版本不能编辑")
                    .foregroundStyle(.secondary)
                Spacer()
                remove
            }
        }
    }

    @ViewBuilder
    private func valueControl(_ i: Int, _ c: FilterCondition, _ field: FilterField) -> some View {
        if field == .keyword {
            TextField("文字", text: Binding(get: { c.values.first ?? "" }, set: { model.setKeyword(at: i, $0) }), prompt: Text("文字"))
                .labelsHidden()
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif
        } else {
            FilterValuePicker(
                field: field,
                values: Binding(get: { c.values }, set: { model.setValues(at: i, $0) }),
                context: context
            )
        }
    }
}

/// One priority chip of the simple form: filled when chosen (a plain
/// toggle-style button looked the same chosen or not on iOS).
private struct PriorityChip: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        let button = Button(label, action: action)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .accessibilityAddTraits(on ? .isSelected : [])
        if on {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered).tint(.secondary)
        }
    }
}
