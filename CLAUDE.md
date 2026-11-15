# OpenTodo

多端待办应用（Flutter 客户端 + Go 同步服务），功能上参考滴答清单。开始工作前先读 [docs/development.md](docs/development.md)：现状、代码地图、环境、踩过的坑、部署和下一步都在里面。本机和服务器的私有信息在 `CLAUDE.local.md`（不进仓库）。

几条必须遵守的：

- Flutter 3.50 的 Material 是独立包，只用 `import 'package:material_ui/material_ui.dart'`。
- 改了 `app/lib/data/db.dart` 的表结构：`schemaVersion` 加一、写 `onUpgrade` 迁移、跑 `dart run build_runner build`。
- 要同步的字段改动，`app/lib/sync/codec.dart` 两个方向都要改，读的一侧给默认值。
- 同步引擎先应用拉回的记录，再标记推送成功，顺序不能反。
- 改完跑 `flutter analyze`、`flutter test`（在 `app/`）和 `go test ./...`（在 `server/`）。
- 更新线上服务用 `server/deploy/deploy.sh`（需要 `OPENTODO_HOST`）。
- 仓库是公开的：服务器地址、本机路径这类私有信息只写进 `CLAUDE.local.md`。
- `reference/` 里的竞品截图只作参考，名字、图标、文案不能进产品。
