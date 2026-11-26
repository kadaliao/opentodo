// What a window does for the system integration (docs/apple.md, 系统集成),
// attached once at the root:
//
// - `opentodo://` links (widgets, the share extension, App Intents, the
//   menu bar window) and Spotlight results open the task / list / view /
//   module;
// - the window's model is registered with `SystemSync`, which keeps it up
//   to date with other processes' writes. Widgets and Spotlight follow the
//   database there too, for the whole process, windows or not.

import CoreSpotlight
import OpenTodoSystem
import SwiftUI

struct SystemIntegration: ViewModifier {
    @Environment(AppModel.self) private var model
    let route: DebugRoute?

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                if let link = AppLink(url) { open(link) }
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String { open(.task(id)) }
            }
            #if os(macOS)
            // Links go to this window rather than opening a new one.
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            #endif
            .task { SystemSync.shared.register(model) }
            .modifier(SystemDebugPresenter(route: route))
    }

    private func open(_ link: AppLink) {
        switch link {
        case .task(let id): model.applyWhenLoaded(.task(id))
        case .list(let id): model.applyWhenLoaded(.list(id))
        case .today: model.applyWhenLoaded(.smart(SmartKind.today.rawValue))
        case .quickAdd:
            model.switchTo(.tasks)
            model.requestQuickAdd()
        case .habits: model.switchTo(.habits)
        case .countdowns: model.switchTo(.countdowns)
        case .focus: model.switchTo(.focus)
        }
    }
}

/// The Spotlight index of open tasks.
enum Spotlight {
    static let domain = "tasks"

    static func index(_ entries: [SpotlightEntry]) async {
        let index = CSSearchableIndex.default()
        let items = entries.map { e in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = e.title
            attributes.contentDescription = e.details
            attributes.keywords = e.keywords
            return CSSearchableItem(uniqueIdentifier: e.id, domainIdentifier: domain, attributeSet: attributes)
        }
        try? await index.deleteSearchableItems(withDomainIdentifiers: [domain])
        guard !items.isEmpty else { return }
        try? await index.indexSearchableItems(items)
    }
}
