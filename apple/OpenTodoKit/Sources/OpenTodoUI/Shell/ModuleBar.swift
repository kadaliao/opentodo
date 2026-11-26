// macOS: the modules as a row of icons at the top of the sidebar, the way
// Xcode switches its navigators. There's room for eight or so, and the
// 显示 menu has them too (⌘1, ⌘2 …). iOS uses tabs instead, so this adds
// nothing there.

import OpenTodoDomain
import SwiftUI

extension View {
    /// Puts the module bar at the top of a sidebar column.
    func moduleBar() -> some View {
        #if os(macOS)
        safeAreaBar(edge: .top, spacing: 0) { ModuleBar() }
        #else
        self
        #endif
    }
}

#if os(macOS)
struct ModuleBar: View {
    @Environment(\.uiScale) private var s
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 2 * s) {
            ForEach(AppModule.allCases) { m in
                let selected = m == model.module
                Button {
                    model.switchTo(m)
                } label: {
                    Image(systemName: m.symbol)
                        .symbolVariant(selected ? .fill : .none)
                        .uiFont(size: 14, weight: selected ? .semibold : .regular)
                        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        // Narrower than this when the sidebar is (界面大小 特大
                        // in the smallest window).
                        .frame(minWidth: 22, idealWidth: 30 * s, maxWidth: 30 * s, minHeight: 24 * s, maxHeight: 24 * s)
                        .background(selected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 6 * s, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Room goes to the icons first, the spacer gets the rest.
                .layoutPriority(1)
                .help("\(m.title) (⌘\(String(m.shortcut.character)))")
                .accessibilityLabel(m.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12 * s)
        .padding(.top, 2 * s)
        .padding(.bottom, 6 * s)
    }
}
#endif
