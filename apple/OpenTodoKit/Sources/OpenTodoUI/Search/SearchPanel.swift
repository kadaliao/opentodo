// macOS search: a Spotlight-like panel near the top of the window (⌘F, or
// the toolbar's magnifying glass). ↑↓ move through the results, Return
// opens one, Esc or a click outside closes it.
//
//     content.searchOverlay(isPresented: $searching) {
//         SearchPanel(
//             data: SearchData(tasks: …, checklist: …, lists: …, tags: …, filters: …),
//             now: .now(),
//             recentSearches: recent.queries,
//             onOpen: { target in reveal(target) },        // then the panel closes
//             onToggleDone: { task, done in repo.setCompleted(task, done) },
//             onRecentSearchesChange: { queries in save(queries) },
//             onClose: { searching = false }
//         )
//     }
//
// The panel shows what it's given and reports what was done; it doesn't
// touch the database. Text still being composed (pinyin not yet turned
// into characters) isn't searched for.

#if os(macOS)
import AppKit
import OpenTodoDomain
import SwiftUI

public struct SearchPanel: View {
    let data: SearchData
    let now: LocalDateTime
    let recentSearches: [String]
    let onOpen: (SearchTarget) -> Void
    let onToggleDone: (TodoTask, Bool) -> Void
    let onRecentSearchesChange: ([String]) -> Void
    let onClose: () -> Void

    @State private var text: String
    /// `text` without what's still being composed.
    @State private var query: String
    @State private var memo = SearchMemo()
    @State private var cursor = SearchCursor()

    /// `onOpen` gets the chosen result, then `onClose` is called.
    /// `onRecentSearchesChange` gets the new list (newest first) to store
    /// whenever a result is opened or a recent search removed.
    public init(
        data: SearchData,
        now: LocalDateTime,
        recentSearches: [String] = [],
        initialQuery: String = "",
        onOpen: @escaping (SearchTarget) -> Void,
        onToggleDone: @escaping (TodoTask, Bool) -> Void = { _, _ in },
        onRecentSearchesChange: @escaping ([String]) -> Void = { _ in },
        onClose: @escaping () -> Void
    ) {
        self.data = data
        self.now = now
        self.recentSearches = recentSearches
        self.onOpen = onOpen
        self.onToggleDone = onToggleDone
        self.onRecentSearchesChange = onRecentSearchesChange
        self.onClose = onClose
        _text = State(initialValue: initialQuery)
        _query = State(initialValue: initialQuery)
    }

    public var body: some View {
        let recent = RecentSearches(recentSearches)
        let model = memo.model(query: query, data: data, recent: recent)
        let active = cursor.active(in: model)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                PanelSearchField(
                    text: $text,
                    placeholder: "搜索",
                    onChange: { query = $0 },
                    onMove: { cursor.move($0, in: model) },
                    onSubmit: { if let active { open(model.entries[active], model, recent) } },
                    onCancel: onClose
                )
                if !text.isEmpty {
                    Button {
                        text = ""
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .help("清除")
                    .accessibilityLabel("清除")
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 54)

            Divider()

            results(model, active: active, recent: recent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 470)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .onChange(of: query) { cursor.reset() }
    }

    @ViewBuilder
    private func results(_ model: SearchModel, active: Int?, recent: RecentSearches) -> some View {
        if model.entries.isEmpty {
            SearchPlaceholder(model: model)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(model.sections) { section in
                            sectionHeader(section, recent: recent)
                            ForEach(Array(section.entries.enumerated()), id: \.element.id) { i, entry in
                                row(entry, model: model, recent: recent, active: active == section.start + i)
                                    .id(entry.id)
                            }
                        }
                        if let note = model.moreTasksNote {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.automatic)
                .onChange(of: active) { _, new in
                    guard let new, model.entries.indices.contains(new) else { return }
                    proxy.scrollTo(model.entries[new].id)
                }
            }
        }
    }

    private func sectionHeader(_ section: SearchSection, recent: RecentSearches) -> some View {
        HStack {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if section.kind == .recent {
                Button("清除") { onRecentSearchesChange([]) }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func row(_ entry: SearchEntry, model: SearchModel, recent: RecentSearches, active: Bool) -> some View {
        Group {
            switch entry {
            case .recent(let q):
                SearchRecentRow(query: q) { onRecentSearchesChange(recent.removing(q).queries) }
            case .task(let hit):
                SearchTaskRow(hit: hit, lists: data.listsById, now: now, onToggleDone: onToggleDone)
            default:
                SearchViewRow(entry: entry, terms: model.terms)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if active {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
            }
        }
        .contentShape(.rect)
        .onTapGesture { open(entry, model, recent) }
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func open(_ entry: SearchEntry, _ model: SearchModel, _ recent: RecentSearches) {
        guard let target = entry.target else {
            if case .recent(let q) = entry {
                text = q
                query = q
            }
            return
        }
        let after = recentAfterOpening(entry, query: model.query, recent: recent)
        if after != recent { onRecentSearchesChange(after.queries) }
        onOpen(target)
        onClose()
    }
}

extension View {
    /// Shows `panel` floating near the top of this view while `isPresented`;
    /// a click outside it closes it.
    public func searchOverlay<Panel: View>(isPresented: Binding<Bool>, @ViewBuilder panel: () -> Panel) -> some View {
        let panel = panel()
        return overlay {
            if isPresented.wrappedValue {
                GeometryReader { geo in
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.0001)
                            .contentShape(.rect)
                            .onTapGesture { isPresented.wrappedValue = false }
                        panel
                            .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
                            .padding(.top, max(16, geo.size.height * 0.12))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(.snappy(duration: 0.18), value: isPresented.wrappedValue)
    }
}

/// The panel's text field: AppKit's, so arrow keys, Return and Esc can be
/// handled while typing and text still being composed can be told apart.
struct PanelSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    /// The text without what's still being composed.
    let onChange: (String) -> Void
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 22, weight: .regular)
        field.placeholderString = placeholder
        field.cell?.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.stringValue = text
        field.setAccessibilityLabel(placeholder)
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
            field.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PanelSearchField

        init(_ parent: PanelSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
            if let editor = field.currentEditor() as? NSTextView {
                parent.onChange(committedQuery(editor))
            } else {
                parent.onChange(field.stringValue)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            default: return false
            }
            return true
        }
    }
}
#endif
