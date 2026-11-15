# OpenTodo

开源的多端待办清单：手机和电脑共用一套 Flutter 客户端，Go 写的同步服务可以自己部署。

> 早期开发中。本地任务管理、多端同步、提醒、重复任务和日历已经可用，搜索、看板等还在路上，见[路线图](docs/roadmap.md)。

## 功能

- 智能清单：今天（含已过期）、明天、最近 7 天、收集箱、已完成、垃圾桶
- 自建清单、标签、优先级、子任务、备注
- 快速添加时识别中文日期：输入“明天下午3点开会 #工作 !高”，自动拆出日期、时间、标签和优先级，边输入边高亮；“每周一9点例会”“每月15号还信用卡”会设成重复任务
- 提醒：准时、提前几分钟到几天，可以设多个；到点由系统弹出通知，应用没开着也会提醒
- 重复任务：每天、每周几、每月几号或第几个周几、每年、工作日、自定义间隔和结束条件；可以按到期日期或完成日期算下一次
- 日历：月、周、3 天、日、日程；拖动任务改日期和时间，点空白处新建；重复任务会显示以后的日期
- 本地优先：没有网络也能用，联网后自动增量同步；冲突时较新的修改胜出
- 电脑上左边一列切换任务和日历，任务三栏布局；手机上底部切换，单栏加抽屉

## 技术栈

| 目录 | 内容 |
|---|---|
| `app/` | Flutter 客户端（iOS、Android、macOS、Windows、Linux），drift（SQLite）+ Riverpod |
| `server/` | Go 同步服务，SQLite，单个可执行文件 |
| `docs/` | [开发文档](docs/development.md)、[架构](docs/architecture.md)、[路线图](docs/roadmap.md) |

## 开发

需要 Flutter 3.50+（Dart 3.14）、Go 1.27+，iOS/macOS 还需要 Xcode。

```sh
# 客户端（在 app/ 下）
flutter pub get
dart run build_runner build      # 改了 lib/data/db.dart 的表结构后重新生成代码
flutter analyze
flutter test                     # 同步集成测试会编译并启动一个服务端；没装 Go 时跳过
flutter run -d macos

# 同步服务（在 server/ 下）
go test ./...
go run ./cmd/opentodo-server     # 监听 127.0.0.1:8686，数据在 data/opentodo.db
```

客户端默认连官方同步服务 `https://todo.liaoxingyi.com`。用自己的服务时，在登录框的“服务器”里填地址，比如本地的 `http://127.0.0.1:8686`。

自己部署同步服务的步骤见[开发文档](docs/development.md#6-部署和运维)。

## 许可证

[AGPL-3.0](LICENSE)。可以自由使用、修改和分发；如果把修改后的版本作为网络服务提供给别人，也要公开相应的源代码。

Copyright © 2026 Kada Liao
