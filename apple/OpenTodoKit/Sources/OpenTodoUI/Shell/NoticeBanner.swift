// The note at the bottom of the window (`Notices`): a small glass capsule
// with the text and, when there's one, 撤销. It sits above the tab bar on
// iOS and over the bottom of the list on macOS, and goes by itself.

import SwiftUI

struct NoticeBanner: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let notice = model.notices.current {
                HStack(spacing: 12) {
                    Text(notice.text)
                        .font(.callout)
                        .lineLimit(2)
                    if notice.action != nil {
                        Button(notice.actionLabel) {
                            Task { await model.notices.runAction() }
                        }
                        .font(.callout.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: Capsule())
                .padding(.bottom, bottomInset)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(notice.id)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.snappy, value: model.notices.current?.id)
    }

    private var bottomInset: CGFloat {
        #if os(iOS)
        76
        #else
        20
        #endif
    }
}
