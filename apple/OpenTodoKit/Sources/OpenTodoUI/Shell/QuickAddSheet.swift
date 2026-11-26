// iPhone (and a board, which has no field at the top): 新建任务 as a short sheet over the list, the keyboard up at once.
// The same field as on the wide layouts (highlighting, the parsed date);
// return adds the task to the current view and closes the sheet, as the
// Flutter version's bottom sheet does.

import OpenTodoDomain
import SwiftUI

struct QuickAddSheet: View {
    @Environment(\.uiScale) private var s
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12 * s) {
                QuickAddField(focusRequests: 1) { _ in dismiss() }
                Text("可以直接写“明天下午3点”“每周一”“#标签”“!高”")
                    .uiFont(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20 * s)
            .padding(.top, 8 * s)
            .navigationTitle("新建任务")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 440 * s, height: 150 * s)
        #else
        .presentationDetents([.height(190)])
        #endif
    }
}
