// macOS: the menu bar window (MenuBarExtra, window style): today's tasks
// (tick to finish, click to open the task in the main window), a quick-add
// line for today, and today's focus time. 设置 → 快速添加 turns it off.

#if os(macOS)
import AppKit
import OpenTodoSystem
import SwiftUI

public struct MenuBarScene: Scene {
    @AppStorage(IntegrationPrefs.menuBarKey) private var shown = true

    public init() {}

    public var body: some Scene {
        MenuBarExtra("OpenTodo", systemImage: "checklist", isInserted: $shown) {
            MenuBarWindow()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Made when the window first opens, on the shared accessory model.
private struct MenuBarWindow: View {
    var body: some View {
        MenuBarContent().environment(SystemServices.shared.model)
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var focusSeconds = 0

    static let width: CGFloat = 340

    private var today: TodayWidget {
        todayWidget(model.data.tasks, lists: model.lists, now: model.now, limit: 50)
    }

    private var target: QuickAddTarget {
        let d = quickAddDefaults(.smart(.today), model.today)
        return QuickAddTarget(listId: d.listId, date: d.date)
    }

    var body: some View {
        let today = self.today
        VStack(spacing: 0) {
            header(today)
            QuickAddField(target: target, prompt: "添加到今天，回车创建")
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            Divider()
            if today.tasks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(.tint)
                    Text("今天没有任务了").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(today.tasks) { line in
                            if let task = model.task(line.id) { row(task) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .frame(width: Self.width)
        .task(id: model.database.url) {
            do {
                for try await sessions in model.database.observeFocusSessions().values() {
                    focusSeconds = focusSummary(sessions, on: Day.today(in: model.timeZone), in: model.timeZone).seconds
                }
            } catch {}
        }
    }

    private func header(_ today: TodayWidget) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("今天").font(.title3.weight(.semibold))
            Text("\(model.today.month)月\(model.today.day)日 \(weekdayName(model.today))")
                .foregroundStyle(.secondary)
            Spacer()
            if today.total > 0 {
                Text("\(today.total) 项")
                    .foregroundStyle(today.overdue > 0 ? Color.red : Color.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func row(_ task: TodoTask) -> some View {
        MenuBarRow(task: task) {
            openURL(AppLink.task(task.id).url())
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                openURL(AppLink.focus.url())
            } label: {
                Label("今日专注 \(focusDurationText(seconds: focusSeconds))", systemImage: "timer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .help("打开专注")
            Spacer()
            Button {
                openURL(AppLink.today.url())
            } label: {
                Image(systemName: "macwindow")
            }
            .help("打开 OpenTodo")
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("设置")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}

/// A task in the menu bar window: the app's own row, the whole line a
/// button that opens it, highlighted under the pointer like a menu item.
private struct MenuBarRow: View {
    @Environment(AppModel.self) private var model
    let task: TodoTask
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        TaskRow(task, now: model.now, list: model.listsById[task.listId], showList: true) {
            Task { await model.setDone(task, task.status == .open) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(hovering ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .padding(.horizontal, 6)
        .accessibilityAction(named: "打开", open)
    }
}
#endif
