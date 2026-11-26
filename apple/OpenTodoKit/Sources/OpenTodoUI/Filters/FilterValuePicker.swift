// Choosing a condition's values: a pop-up with check boxes on macOS, a
// page of checkmarks on iOS (as Settings does). A date condition also
// offers a custom range (自定义范围).

import OpenTodoDomain
import SwiftUI

/// What the picker needs to know about the world.
struct FilterPickerContext {
    var lists: [TaskList]
    var tags: [String]
    var today: Day

    var liveLists: [String: TaskList] {
        Dictionary(lists.filter { $0.deletedAt == nil }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func summary(_ field: FilterField, _ values: [String]) -> String {
        describeValues(field, values, lists: liveLists, today: today)
    }
}

struct FilterValuePicker: View {
    let field: FilterField
    @Binding var values: [String]
    let context: FilterPickerContext
    /// The row's label (普通) or none (高级, where the field is chosen beside it).
    var label: String?

    #if os(macOS)
    @State private var open = false
    #endif

    var body: some View {
        #if os(macOS)
        let button = Button {
            open.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(context.summary(field, values))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: label == nil ? .leading : .trailing)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            FilterValueChecklist(field: field, values: $values, context: context)
                .frame(width: 260)
                .frame(maxHeight: 420)
        }
        .accessibilityLabel(label ?? field.label)
        .accessibilityValue(context.summary(field, values))
        if let label {
            LabeledContent(label) { button }
        } else {
            button
        }
        #else
        NavigationLink {
            FilterValueChecklist(field: field, values: $values, context: context)
                .navigationTitle(label ?? field.label)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            if let label {
                LabeledContent(label, value: context.summary(field, values))
            } else {
                Text(context.summary(field, values))
                    .lineLimit(1)
            }
        }
        #endif
    }
}

/// The choices with a tick each; for dates, the custom range after them.
struct FilterValueChecklist: View {
    let field: FilterField
    @Binding var values: [String]
    let context: FilterPickerContext

    var body: some View {
        let options = filterValueOptions(field, values: values, lists: context.lists, tags: context.tags)
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(options) { o in
                    Toggle(o.label, isOn: tick(o, options))
                        .toggleStyle(.checkbox)
                }
                if field == .date {
                    Divider().padding(.vertical, 2)
                    rangeEditor
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        #else
        Form {
            Section {
                ForEach(options) { o in
                    Button {
                        values = toggling(o.value, in: values, options: options)
                    } label: {
                        HStack {
                            Text(o.label).foregroundStyle(.primary)
                            Spacer()
                            if values.contains(o.value) {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(values.contains(o.value) ? .isSelected : [])
                }
            }
            if field == .date {
                Section { rangeEditor }
            }
        }
        #endif
    }

    private func tick(_ o: FilterValueOption, _ options: [FilterValueOption]) -> Binding<Bool> {
        Binding(
            get: { values.contains(o.value) },
            set: { _ in values = toggling(o.value, in: values, options: options) }
        )
    }

    private var range: FilterDateRange? {
        FilterCondition(.date, values).dateRange
    }

    @ViewBuilder private var rangeEditor: some View {
        let today = context.today
        Toggle("自定义范围", isOn: Binding(
            get: { range != nil },
            set: { on in
                values = FilterCondition(.date, values).values(settingRange: on ? FilterDateRange(today, today + 6) : nil)
            }
        ))
        #if os(macOS)
        .toggleStyle(.checkbox)
        #endif
        if let range {
            DatePicker("开始", selection: day(range.start) { FilterDateRange($0, max($0, range.end)) }, displayedComponents: .date)
            DatePicker("结束", selection: day(range.end) { FilterDateRange(min($0, range.start), $0) }, displayedComponents: .date)
        }
    }

    /// A `Date` binding for one end of the range; `make` builds the range
    /// from the day picked.
    private func day(_ d: Day, _ make: @escaping (Day) -> FilterDateRange) -> Binding<Date> {
        Binding(
            get: { d.start() },
            set: { values = FilterCondition(.date, values).values(settingRange: make(Day($0))) }
        )
    }
}
