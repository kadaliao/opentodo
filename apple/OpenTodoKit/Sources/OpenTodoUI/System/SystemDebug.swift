// `-OTOpen system:<state>` (debug builds, macOS): the menu bar window and
// the quick-add panel laid out inside the main window, where screenshots
// can see them (they're windows of their own otherwise, and a global
// shortcut can't be pressed by a script). On the accessory model, so they
// show the same data the real ones would.
//
//     system:menubar      the menu bar window
//     system:quickpanel   the quick-add panel, with `-OTQuickAdd <text>` typed in
//     system:settings     设置 → 快速添加

import OpenTodoSystem
import SwiftUI

enum SystemDebugState: String, CaseIterable {
    case menubar, quickpanel, settings
}

struct SystemDebugPresenter: ViewModifier {
    let route: DebugRoute?

    private var state: SystemDebugState? {
        if case .system(let s) = route { SystemDebugState(rawValue: s) } else { nil }
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        if let state {
            content.overlay(alignment: state == .menubar ? .topTrailing : .top) {
                SystemDebugCard(state: state)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if os(macOS)
private struct SystemDebugCard: View {
    let state: SystemDebugState

    var body: some View {
        let model = SystemServices.shared.model
        Group {
            switch state {
            case .menubar:
                MenuBarContent()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
                    .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
                    .padding(.top, 8)
                    .padding(.trailing, 60)
            case .quickpanel:
                QuickAddPanelView(state: QuickAddPanelState()) {}
                    // -OTSnapshot can't draw the glass: a plain backing to see the layout.
                    .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
                    .padding(.top, 140)
            case .settings:
                IntegrationSettingsPane()
                    .frame(width: 480, height: 380)
                    .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))
                    .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
                    .padding(.top, 100)
            }
        }
        .environment(model)
    }
}
#endif
