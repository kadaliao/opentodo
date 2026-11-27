# OpenTodo

多端待办应用，功能上参考滴答清单。三部分：

- `apple/`：苹果平台（macOS、iOS）的客户端，Swift 原生。先读 [docs/apple.md](docs/apple.md)：结构、约定、怎么验证、踩过的坑都在里面。
- `app/`：Flutter 客户端。苹果平台已经换成 Swift 版，Flutter 版留着当规格（Swift 版的行为照它）和以后别的平台用。先读 [docs/development.md](docs/development.md)。
- `server/`：Go 同步服务，两个客户端连同一个账号。

本机和服务器的私有信息在 `CLAUDE.local.md`（不进仓库）。

## 都要遵守的

- 仓库是公开的：服务器地址、本机路径这类私有信息只写进 `CLAUDE.local.md`。
- `reference/` 里的竞品截图只作参考，名字、图标、文案不能进产品。
- 要同步的字段改动，两个客户端的 codec 两个方向都要改（Swift：`apple/OpenTodoKit/Sources/OpenTodoData/Codec.swift`；Flutter：`app/lib/sync/codec.dart`），读的一侧给默认值。
- 同步引擎先应用拉回的记录，再标记推送成功，顺序不能反。
- 新加一种要同步的数据，先部署服务端（`server/deploy/deploy.sh`，需要 `OPENTODO_HOST`）再发客户端。
- 改完 `server/` 跑 `go test ./...`。

## Swift 版（`apple/`）

- 数据库结构和 Flutter 版一致（schema 7 以前完全相同，8 起是 Swift 版加的）。加表加列：版本加一、写迁移、不能删库重建；加了同步类型的那次迁移把 `sync.cursor` 归零。
- 调试版包名 `com.liaoxingyi.opentodo.dev`，正式版 `com.liaoxingyi.opentodo`（和 Flutter 版同一个，直接接着用它的数据）。测试和截图用临时数据库。
- 改完跑 `cd apple/OpenTodoKit && swift build && swift test`，再跑 `apple/scripts/build.sh macos` 和 `build.sh ios`。界面改动看截图（`apple/scripts/shot.sh`）。
- 用户能看到的改动记进根目录 `CHANGELOG.md` 的“未发布”。发版（macOS）：改 `MARKETING_VERSION`，`apple/scripts/release.sh --publish` 签名、公证、建 GitHub Release、更新 Homebrew tap，步骤见 docs/apple.md 的“发布”。
- 不用模拟键盘鼠标去点真实窗口（会落进用户正在用的窗口）；要点界面用模拟器里的 XCUITest，或 `-OTOpen` 路由直接打开那个状态。
- 几个 agent 并行时各用各的 git worktree；**同一时间最多一个开 iOS 模拟器**（七个模拟器同时开把机器拖垮过），其余只编不截。

## Flutter 版（只对 `app/` 有效）

- Flutter 3.50 的 Material 是独立包，只用 `import 'package:material_ui/material_ui.dart'`。
- 改了 `app/lib/data/db.dart` 的表结构：`schemaVersion` 加一、写 `onUpgrade` 迁移、跑 `dart run build_runner build`。
- 改完跑 `flutter analyze`、`flutter test`（在 `app/`）。
