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
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppModule.allCases) { m in
                let selected = m == model.module
                Button {
                    model.switchTo(m)
                } label: {
                    Image(systemName: m.symbol)
                        .symbolVariant(selected ? .fill : .none)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 30, height: 24)
                        .background(selected ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(m.title) (⌘\(String(m.shortcut.character)))")
                .accessibilityLabel(m.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }
}
#endif
