// The share extension: text or a link shared from another app becomes a
// task in the inbox (or a list picked here). The title is the page's title
// or the text, the link goes in the description (`shareDraft`, tested in
// OpenTodoSystem); it is written to the shared database (`SharedWriter`)
// and the app sends it with its next sync.

import Observation
import OpenTodoSystem
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor @Observable
final class ShareModel {
    var title = ""
    var content = ""
    var listId = inboxListId
    var lists: [TaskList] = []
    var loading = true
    var saving = false
    var error: String?

    @ObservationIgnored var finish: (Bool) -> Void = { _ in }
    @ObservationIgnored private var writer: SharedWriter?

    var canSave: Bool { !loading && !saving && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func load(_ items: [NSExtensionItem]) async {
        do {
            writer = try SharedWriter.open()
            lists = try await writer?.lists() ?? []
        } catch {
            self.error = "打不开 OpenTodo 的数据：\(error.localizedDescription)"
        }
        let draft = shareDraft(await Self.sharedItem(items))
        title = draft.title
        content = draft.content
        loading = false
    }

    func save() {
        guard let writer, canSave else { return }
        saving = true
        Task {
            do {
                try await writer.add(title: title.trimmingCharacters(in: .whitespacesAndNewlines), content: content,
                                     listId: listId)
                finish(true)
            } catch {
                self.error = "没存上：\(error.localizedDescription)"
                saving = false
            }
        }
    }

    /// The text, link and page title among what was shared.
    static func sharedItem(_ items: [NSExtensionItem]) async -> SharedItem {
        var shared = SharedItem()
        var texts: [String] = []
        for item in items {
            let heading = (item.attributedTitle?.string).flatMap { $0.isEmpty ? nil : $0 }
            let body = (item.attributedContentText?.string).flatMap { $0.isEmpty ? nil : $0 }
            for provider in item.attachments ?? [] {
                if shared.url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await load(URL.self, from: provider), url.scheme == "http" || url.scheme == "https" {
                    shared.url = url
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = await load(String.self, from: provider) {
                    texts.append(text)
                }
            }
            if shared.pageTitle == nil { shared.pageTitle = heading }
            // With a link, the item's text is usually the page's title.
            if let body {
                if shared.url != nil && shared.pageTitle == nil { shared.pageTitle = body } else if !texts.contains(body) { texts.append(body) }
            }
        }
        shared.text = texts.isEmpty ? nil : texts.joined(separator: "\n")
        return shared
    }

    private static func load<T: _ObjectiveCBridgeable & Sendable>(_ type: T.Type, from provider: NSItemProvider) async -> T?
        where T._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: type) { value, _ in continuation.resume(returning: value) }
        }
    }
}

struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        #if os(iOS)
        NavigationStack {
            form
                .navigationTitle("添加到 OpenTodo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { model.finish(false) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) { model.save() }.disabled(!model.canSave)
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            Text("添加到 OpenTodo").font(.headline).padding(.top, 14)
            form
            Divider()
            HStack {
                Spacer()
                Button("取消") { model.finish(false) }.keyboardShortcut(.cancelAction)
                Button("保存") { model.save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
            .padding(12)
        }
        .frame(width: 400)
        #endif
    }

    private var form: some View {
        Form {
            Section {
                TextField("标题", text: $model.title, axis: .vertical)
                    .lineLimit(1...4)
                if !model.content.isEmpty {
                    Text(model.content)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }
            Section {
                Picker("清单", selection: $model.listId) {
                    Label("收集箱", systemImage: "tray").tag(inboxListId)
                    ForEach(model.lists) { l in
                        Text([l.emoji, l.name].compactMap { $0 }.joined(separator: " ")).tag(l.id)
                    }
                }
            } footer: {
                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("存进 OpenTodo，下次打开应用时同步。")
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.loading || model.saving)
        .overlay { if model.loading { ProgressView() } }
    }
}

#if os(iOS)
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.finish = { [weak self] saved in
            guard let context = self?.extensionContext else { return }
            if saved {
                context.completeRequest(returningItems: nil)
            } else {
                context.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            }
        }
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { await model.load(items) }
    }
}
#else
final class ShareViewController: NSViewController {
    private let model = ShareModel()

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        model.finish = { [weak self] saved in
            guard let context = self?.extensionContext else { return }
            if saved {
                context.completeRequest(returningItems: nil)
            } else {
                context.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            }
        }
        let host = NSHostingView(rootView: ShareView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 320)
        view = host
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { await model.load(items) }
    }
}
#endif
