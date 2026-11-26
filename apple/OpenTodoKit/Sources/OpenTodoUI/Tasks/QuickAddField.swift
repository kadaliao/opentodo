// The quick-add line: type 明天下午3点开会 #工作 !高 and press return. As
// the text changes it is parsed (`parseQuickAdd`), the recognised parts —
// date, time, repeat, #tags, !priority — get a tinted background, and the
// date it will get shows at the end (明天, 下午3:00 · 每周). Return adds the
// task (`AppModel.quickAdd`) and leaves the field ready for the next.
//
// The highlight is drawn by a `Text` behind a plain `TextField` set in the
// same font, so the field itself is untouched and input methods (pinyin
// composition) work as usual. While the text is wider than the field the
// highlight would no longer line up, so it is left out.
//
//     QuickAddField()                                   // the current view decides
//     QuickAddField(target: QuickAddTarget(listId: "work", sectionId: "s1"),
//                   prompt: "添加到“进行中”")             // a board column's

import OpenTodoDomain
import SwiftUI

public struct QuickAddField: View {
    @Environment(AppModel.self) private var model
    var target: QuickAddTarget?
    var prompt: String?
    /// Called after a task was added (a sheet closes itself).
    var onAdded: ((String) -> Void)?
    /// Focus from outside (⌘N); bumped value = take focus.
    var focusRequests: Int

    @State private var text = ""
    @State private var parsed: QuickAddResult?
    @State private var fieldWidth: CGFloat = 0
    @FocusState private var focused: Bool
    @Environment(\.uiScale) private var s

    public init(target: QuickAddTarget? = nil, prompt: String? = nil, focusRequests: Int = 0,
                onAdded: ((String) -> Void)? = nil) {
        self.target = target
        self.prompt = prompt
        self.focusRequests = focusRequests
        self.onAdded = onAdded
    }

    public var body: some View {
        HStack(spacing: TaskRow.Metrics.gap * s) {
            Image(systemName: "plus")
                .uiFont(.body, weight: .medium)
                .foregroundStyle(.tint)
                .frame(width: PriorityCheckbox.defaultSize * s)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .uiFont(Self.font)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(submit)
                .accessibilityLabel("添加任务")
                // Behind the field and not part of its size: when the text
                // is wider than the field (it hides then) it mustn't push
                // the date beside it out of the row.
                .background(alignment: .leading) { highlight }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fieldWidth = $0 }
            if let preview {
                Label(preview.text, systemImage: preview.repeats ? "repeat" : "calendar")
                    .uiFont(.caption)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .padding(.horizontal, 8 * s)
                    .padding(.vertical, 3 * s)
                    .background(.tint.opacity(0.12), in: Capsule())
                    .fixedSize()
                    .accessibilityLabel("识别为 \(preview.text)")
            }
        }
        .onChange(of: text) { reparse() }
        .onChange(of: focusRequests) { focused = true }
        .onAppear {
            if target == nil, let text = model.taskList.takePrefill() {
                self.text = text
                focused = true
            } else if focusRequests > 0 {
                focused = true
            }
        }
    }

    /// The field's and the highlight's: the same, so they line up.
    static let font = Font.TextStyle.body

    private var placeholder: String {
        if let prompt { return prompt }
        let listId = target?.listId ?? quickAddDefaults(model.view, model.today, model.filterRules).listId
        return "添加任务至“\(listName(listId, model.listsById))”，回车创建"
    }

    /// The same text, clear, with the recognised parts' backgrounds.
    @ViewBuilder private var highlight: some View {
        if let parsed, !parsed.tokens.isEmpty {
            Text(highlighted(text, parsed.tokens))
                .uiFont(Self.font)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
                .opacity(textWidth <= fieldWidth ? 1 : 0)
        }
    }

    @State private var textWidth: CGFloat = 0

    private func highlighted(_ text: String, _ tokens: [QuickAddToken]) -> AttributedString {
        var a = AttributedString(text)
        a.foregroundColor = .clear
        for t in tokens {
            guard t.end <= text.utf16.count,
                  let r = Range(t.range(in: text), in: a) else { continue }
            a[r].backgroundColor = Color.accentColor.opacity(0.22)
        }
        return a
    }

    private var preview: (text: String, repeats: Bool)? {
        guard let parsed, let date = parsed.date else { return nil }
        var parts = [fullDueLabel(date, parsed.time, today: model.today, duration: parsed.duration)]
        if let rule = parsed.repeat { parts.append(describeRepeat(rule, date)) }
        return (parts.joined(separator: " · "), parsed.repeat != nil)
    }

    private func reparse() {
        parsed = text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : parseQuickAdd(text, now: model.now)
    }

    private func submit() {
        let line = text
        guard parsed.map({ !$0.title.isEmpty }) == true else { return }
        text = ""
        focused = true
        Task {
            if let id = await model.quickAdd(line, target: target) { onAdded?(id) }
        }
    }
}
