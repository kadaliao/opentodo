// How callers show the date dialog: attached to the control that opens it
// (the detail's date button, a toolbar button), it is a popover on macOS
// and iPad and a sheet with detents on iPhone.
//
//     Button(dueText) { editing = true }
//         .scheduleEditor(isPresented: $editing, schedule: ScheduleDraft(task: task),
//                         defaults: settings.defaults,
//                         notificationsAllowed: reminders.allowed,
//                         openNotificationSettings: reminders.openSettings) { draft in
//             try repo.setSchedule(task.id, draft)
//         }
//
// From a context menu or a batch action there is no control to point at:
// put the same modifier on the list (or use `ScheduleEditorView` in a
// `.sheet` directly).

import OpenTodoDomain
import SwiftUI

extension View {
    /// Shows the date dialog while `isPresented` is true. `onCommit` gets
    /// the new schedule (`ScheduleDraft.cleared` for 清除); cancelling or
    /// dismissing calls nothing.
    public func scheduleEditor(
        isPresented: Binding<Bool>,
        schedule: ScheduleDraft,
        defaults: TaskDefaults = .standard,
        notificationsAllowed: Bool? = nil,
        openNotificationSettings: (() -> Void)? = nil,
        onCommit: @escaping (ScheduleDraft) -> Void
    ) -> some View {
        modifier(SchedulePresenter(
            isPresented: isPresented, schedule: schedule, defaults: defaults,
            notificationsAllowed: notificationsAllowed, openNotificationSettings: openNotificationSettings,
            opening: [], onCommit: onCommit
        ))
    }
}

struct SchedulePresenter: ViewModifier {
    @Binding var isPresented: Bool
    let schedule: ScheduleDraft
    let defaults: TaskDefaults
    let notificationsAllowed: Bool?
    let openNotificationSettings: (() -> Void)?
    let opening: [SchedulePage]
    let onCommit: (ScheduleDraft) -> Void

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        let popover = sizeClass == .regular
        #else
        let popover = false
        #endif
        return content.popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ScheduleEditorView(
                schedule, defaults: defaults, now: .now, timeZone: .current,
                notificationsAllowed: notificationsAllowed, openNotificationSettings: openNotificationSettings,
                opening: opening,
                onCommit: { draft in
                    isPresented = false
                    onCommit(draft)
                },
                onCancel: { isPresented = false }
            )
            .modifier(ScheduleSheetStyle(popover: popover))
        }
    }
}

/// iPhone: a sheet that opens full and can be pulled down to half.
struct ScheduleSheetStyle: ViewModifier {
    @State private var detent = PresentationDetent.large
    /// Shown as a popover (a regular-width window; inside the popover the
    /// size class reads compact, so the presenter tells it).
    var popover = false

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .frame(idealWidth: 390, idealHeight: 760)
            // As a popover (iPad) the form's scrolling let it come out
            // short, with 清除日期 below the fold: tall enough for all of it.
            .frame(minHeight: popover ? 880 : nil)
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.medium, .large], selection: $detent)
            .presentationDragIndicator(.visible)
        #else
        content
        #endif
    }
}
