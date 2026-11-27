# OpenTodo

开源的多端待办清单，Go 写的同步服务可以自己部署。有两个客户端，连同一个账号、用同一种数据：

- **苹果平台（macOS、iOS / iPadOS）用 Swift 原生客户端**（`apple/`），界面用系统自带的组件，像系统的提醒事项和日历。
- **Flutter 客户端**（`app/`）是先做的那一版，功能是 Swift 版的规格，留给 Android、Windows、Linux。

> 早期开发中。本地任务管理、多端同步、提醒、重复任务、日历、搜索、过滤器、看板和时间线两个客户端都有；番茄专注、习惯打卡、倒数日、四象限、小组件、菜单栏和分享扩展目前只在 Swift 版里。见[路线图](docs/roadmap.md)。

## 下载

macOS 版（macOS 26 起，Apple 芯片和 Intel 都能用）：

```sh
brew install --cask kadaliao/tap/opentodo
```

也可以在[发布页](https://github.com/kadaliao/opentodo/releases)下载 DMG，把 OpenTodo 拖进“应用程序”。安装包用 Developer ID 签名并经过苹果公证，每一版的改动见[更新记录](CHANGELOG.md)。iOS / iPadOS 版目前要自己编（见下面“开发”）。

## 功能

- 智能清单：今天（含已过期）、明天、最近 7 天、收集箱、已完成、垃圾桶
- 自建清单、标签、优先级、子任务、备注
- 分组和看板：清单里可以分组，拖动排序、拖到别的分组，分组本身也能拖着换位置；每个清单可以用列表或看板显示，按自定义、时间、标题（按拼音，中英文一起排）或优先级排序；任务可以置顶；在“今天”“最近7天”里把任务拖到别的日子就改了日期，没有任务的日子也能拖进去
- 快速添加时识别中文日期：输入“明天下午3点开会 #工作 !高”，自动拆出日期、时间、标签和优先级，边输入边高亮；“每周一9点例会”“每月15号还信用卡”会设成重复任务
- 提醒：准时、提前几分钟到几天，可以设多个；到点由系统弹出通知，应用没开着也会提醒；通知上可以直接“完成”或“稍后提醒”
- 时间段：任务可以有开始和结束（“下午3点到5点”），也可以跨几天；日历里按时长显示，拖下边缘改结束时间
- 重复任务：每天、每周几、每月几号或第几个周几、每年、工作日、自定义间隔和结束条件；可以按到期日期或完成日期算下一次；法定工作日（跳过节假日、调休上班照常）和农历每年 / 每月
- 日历：月、周、3 天、日、日程；拖动任务改日期和时间，点空白处新建；重复任务会显示以后的日期；标农历、节日和法定节假日的休 / 班
- 多选：电脑上 ⌘ / Shift 点选、⌘A 全选，手机上长按菜单里进“多选”；一起改日期、优先级、清单、标签，一起完成或删除（可撤销），也可以一起拖到别的分组或别的日子
- 搜索：在任务标题、描述、子任务和标签里找，也能找清单、标签和过滤器，命中的词标黄；标题和名字可以用拼音或首字母找（“zhoubao”“zb”都能找到“周报”）；电脑上 ⌘F / Ctrl+F，方向键选、回车打开
- 过滤器：按清单、标签、日期、优先级、内容把任务筛到一起，比如“本周的高优先级工作”；高级模式可以“不包含”、可以“满足任一”；跟着账号同步
- 设置：新任务的默认提醒、时间段默认时长、稍后提醒的时长
- 本地优先：没有网络也能用，联网后自动增量同步；冲突时较新的修改胜出
- 效率模块（Swift 版）：番茄专注（计时、记录、统计）、习惯打卡（连续天数、月历）、倒数纪念日（农历、生日岁数）、四象限
- 系统集成（Swift 版）：桌面小组件（今天、快速添加、倒数日、习惯）、macOS 菜单栏小窗和全局快捷键快速添加、分享扩展、快捷指令、Spotlight

## 技术栈

| 目录 | 内容 |
|---|---|
| `apple/` | Swift 原生客户端（macOS、iOS / iPadOS），SwiftUI + GRDB（SQLite），XcodeGen 生成工程 |
| `app/` | Flutter 客户端（Android、Windows、Linux，也能编苹果平台），drift（SQLite）+ Riverpod |
| `server/` | Go 同步服务，SQLite，单个可执行文件 |
| `docs/` | [开发文档](docs/development.md)、[Swift 版](docs/apple.md)、[架构](docs/architecture.md)、[路线图](docs/roadmap.md) |

## 开发

Swift 版需要 Xcode 27（macOS 26 / iOS 26 SDK）和 XcodeGen；Flutter 版需要 Flutter 3.50+（Dart 3.14）；同步服务和两个客户端的同步集成测试需要 Go 1.27+。

```sh
# Swift 客户端（在 apple/ 下）
(cd OpenTodoKit && swift build && swift test)   # 逻辑、数据、同步、界面模型的测试
./scripts/build.sh macos                        # 生成工程并编 macOS 调试版
./scripts/build.sh ios                          # iOS 模拟器调试版
open .derived/Build/Products/Debug/OpenTodo.app # 调试版用自己的包名和数据库，不碰正式数据
./scripts/shot.sh macos smart:today shot.png    # 用演示数据打开某个界面并截图

# Flutter 客户端（在 app/ 下）
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
