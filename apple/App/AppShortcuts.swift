// The App Shortcuts Siri and the Shortcuts app offer without any setup
// (the intents are in Intents/, shared with the widget extension; this
// provider belongs to the app alone).

import AppIntents

struct OpenTodoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "用\(.applicationName)添加任务",
                "在\(.applicationName)里添加任务",
                "\(.applicationName)添加任务",
            ],
            shortTitle: "添加任务",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: OpenListIntent(),
            phrases: [
                "用\(.applicationName)打开\(\.$list)",
                "在\(.applicationName)里打开\(\.$list)",
            ],
            shortTitle: "打开清单",
            systemImageName: "list.bullet"
        )
    }
}
