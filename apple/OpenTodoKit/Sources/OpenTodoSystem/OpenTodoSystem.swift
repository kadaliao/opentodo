// The system integration's shared part (docs/apple.md, 系统集成): what the
// app, its widget and share extensions and its App Intents have in common.
//
//   AppLink              opentodo://task/<id> and the other links into the app
//   todayWidget …        what the widgets show, when they redraw (WidgetContent)
//   WidgetStore          the shared database, read-only, for the widgets
//   SharedWriter         writes from outside the app (widget buttons, share, intents)
//   ChangeSignal         "the data changed" between processes
//   shareDraft           shared text / links as a task
//   HotKey               the global quick-add shortcut as a value

@_exported import OpenTodoData
