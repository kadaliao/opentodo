// What a view shows when it has no tasks, and the placeholders of the
// detail column and of modules still to come. Wording as the Flutter
// version's `_EmptyState`.

import OpenTodoDomain
import SwiftUI

public struct EmptyState: View {
    public var symbol: String
    public var title: String
    public var hint: String?

    public init(_ title: String, symbol: String, hint: String? = nil) {
        self.symbol = symbol
        self.title = title
        self.hint = hint
    }

    public static func forView(_ view: ViewRef) -> EmptyState {
        switch view {
        case .smart(.today): EmptyState("今天没有任务", symbol: "sun.max", hint: "享受这一天，或者添加一个")
        case .smart(.completed): EmptyState("还没有完成的任务", symbol: "checkmark.circle", hint: "完成的任务会出现在这里")
        case .smart(.trash): EmptyState("垃圾桶是空的", symbol: "trash", hint: "删除的任务会在这里保留，可以恢复")
        case .smart(.inbox): EmptyState("收集箱是空的", symbol: "tray", hint: "想到什么先记在这里，之后再整理")
        case .filter: EmptyState("没有符合条件的任务", symbol: ViewSymbol.filter, hint: "可以调整过滤器的条件")
        default: EmptyState("没有任务", symbol: "checklist", hint: "添加一个任务开始吧")
        }
    }

    /// The detail column with nothing open: just a quiet line, as Mail's
    /// 未选择邮件.
    public static let noTaskSelected = EmptyState("没有选中任务", symbol: "", hint: nil)

    public var body: some View {
        if symbol.isEmpty {
            Text(title)
                .uiFont(.title3)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            unavailable
        }
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let hint { Text(hint) }
        }
    }
}
