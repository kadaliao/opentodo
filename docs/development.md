# 开发文档

接手这个项目先读这一篇。命令速查在 [README](../README.md)，设计细节在 [architecture.md](architecture.md)，完整功能清单在 [roadmap.md](roadmap.md)。

更新于 2026-11-15（日历里多选）。

## 1. 现在做到哪了

OpenTodo 是一个多端待办应用，功能上参考了滴答清单。客户端全部用 Flutter，同步服务用 Go。

| 阶段 | 状态 | 内容 |
|---|---|---|
| M1 本地核心 | 完成 | 清单、任务、子任务；智能清单（今天/明天/最近7天/收集箱/已完成/垃圾桶）；标签；中文自然语言快速添加；任务详情；电脑三栏 / 手机单栏 |
| M2 同步与账号 | 完成 | 邮箱注册登录、推拉合一的增量同步、冲突“新者胜”、删除传播、登录限流、每日备份 |
| 部署 | 完成 | 官方同步服务 `https://todo.liaoxingyi.com` |
| M3 日历 | 完成 | 月、周、3 天、日、日程；拖动改日期和时间、点空白处新建；重复任务展开以后的日期；按清单筛选；农历、节日和休 / 班标注；电脑左侧图标栏 / 手机底部栏切换任务和日历 |
| M4 提醒与重复 | 完成 | 系统通知提醒（多个、自定义）、点通知打开任务、通知上的“完成”“稍后提醒”；重复任务（RRULE 子集、按到期/完成日期、结束条件、跳过、撤销），法定工作日、农历重复；快速添加识别“每周一”“每年农历八月十五”等；时间段任务（开始–结束）；设置页的默认值。遗留的验证见第 8 节 |
| 搜索和过滤器 | 完成 | 搜索任务（标题、描述、子任务、标签）、清单、标签、过滤器，关键词标黄，电脑上 ⌘F / Ctrl+F；过滤器按清单、标签、日期、优先级、内容筛任务，普通 / 高级两种编辑，在侧栏里，跟着账号同步 |
| 看板和分组 | 完成 | 清单（含收集箱）里加分组；列表里分组显示成标题，看板里是列；拖动排序、拖到别的分组；每个清单在这台设备上选列表或看板、排序方式（自定义 / 时间 / 优先级）；任务置顶；今天 / 明天 / 最近7天里拖到别的日子改期 |
| 多选 | 完成 | 电脑上 ⌘ / Ctrl 点选、Shift 连选、⌘A 全选、Esc 取消，右边换成批量面板；手机上从菜单进“多选”，底部一条操作栏；一起改日期、优先级、清单、标签，完成、置顶、复制标题、删除（完成和删除可撤销）；选中的任务一起拖到别的分组、别的位置或别的日子 |
| 清单收尾 | 完成 | 拖动分组本身（列表里拖分组标题，看板里拖列顶）；按标题排序（按拼音，中英文一起排）；今天 / 最近7天里没有任务的日子也显示，好往里拖；搜索可以用拼音和首字母找标题和名字 |
| 分组方式 | 完成 | 列表上方的 ⇅ 按钮：每个视图在这台设备上选分组（清单里是自定义分组 / 时间 / 标签 / 优先级 / 不分组，今天 / 明天 / 最近7天 / 过滤器是时间 / 清单 / 标签 / 优先级 / 不分组，标签视图是清单 / 时间 / 优先级 / 不分组）和排序（多了按标签；只有清单能自定义）；拖进哪一组就改成那组的日期、优先级、清单或标签；看板的列始终是自定义分组 |
| 时间线 | 完成 | 清单（含收集箱）的 ⋯ 里选“时间线”（和列表、看板一样每台设备各选各的）：任务按日期画成横条，跨天的任务画到结束那天，挤不下往下排；有分组时每个分组一条泳道；日 / 周 / 月三档缩放、左右无限滚动、“今天”、当前时刻的红线、周末和法定假日加底色；拖动横条改日期（多选的一起拖），拖进别的泳道换分组，电脑上拖右边缘改结束日期，点空白处在那天新建；旁边一栏“无日期”，拖上时间线就排上日期，拖回来就去掉日期；可以显示已完成 |
| 日历里多选 | 完成 | 电脑上 ⌘ / Ctrl 点选、Shift 按显示顺序连选、⌘A 选这一页、Esc 取消，宽屏右边换成批量面板，窄一点是底部操作栏；选着的时候点空白处是取消选择，不是新建；手机上长按任务不动出菜单（日历的任务条以前没有长按菜单）进“多选”，之后点一下选一个；选中的任务一起拖：都挪同样的天数，拖到小时格上计时的任务挪同样的分钟数，带头的是全天任务时全天的那些排到放下的时刻，拖进“全天”时带头的是计时任务就都去掉时间；选中的任务条颜色加深、加边框（时间线的横条也改成一样） |
| M3 其余、M5 及以后 | 未开始 | 置顶、日历补充、效率模块等，见下面第 8 节 |

验证情况：Flutter 263 个测试（含 9 个“编译并启动真实 Go 服务、两台模拟设备同步”的集成测试）、Go 服务端测试全部通过；macOS 正式版和 iPhone 模拟器实际登录同一账号互相同步过。M4 的新版本在 macOS 上对真实数据跑过 v3 迁移、启动无报错，iOS 模拟器版能编译；系统通知实际弹出还没在真机上看过。日历的各个模式在界面测试里渲染、拖动、新建都验证过（含手机尺寸和深色模式的截图检查），还没在真机上用手拖过。时间段（v4 迁移）在真实数据库的副本上迁移过，对话框和日历看过截图，还没装进 macOS 正式版。通知按钮的处理逻辑有单测和界面测试，iOS 模拟器版和 macOS 调试版能编译，但还没有在系统通知上实际按过（iOS 后台引擎那条路只能真机或模拟器上手动试）。节假日数据照 2025–2027 年的国务院通知录入，农历表和 macOS 的中国历逐条对照过，日历标注看过截图。搜索和过滤器有单测、界面测试（建过滤器、在里面添加、改成高级条件、删除；⌘F 搜索、方向键加回车打开；手机搜索页）和同步集成测试，电脑 / 手机 / 深色的截图看过；v5 迁移（加过滤器表、同步游标归零）在 macOS 正式版和 iPhone 模拟器的真实数据上跑过，过滤器的新建和删除在两边经线上服务互相同步过。线上服务端 2026-11-15 已更新到认识 `filter` 的版本（自己部署的服务端也要先更新，旧版会拒掉整个同步请求）。看板和分组有单测、界面测试（电脑上拖进分组、在分组里拖动排序、重命名和删除分组；看板里跨列拖、在列里添加、切回列表；手机上长按不动出菜单、长按拖动排序）、同步集成测试，电脑 / 深色 / 手机的截图看过；v6 迁移在 macOS 正式版和 iPhone 模拟器的真实数据上跑过，分组的新建和删除在两边经线上服务互相同步过（线上服务端 2026-11-15 已更新到认识 `section` 的版本）。拖动还没在真机上用手试过。置顶（v7 迁移，只加一列，不重新拉取）、排序方式、日期视图拖动改期有单测和界面测试；v7 在 macOS 正式版和 iPhone 模拟器的真实数据上跑过，置顶经线上服务同步过。多选有单测和界面测试（电脑上点选、连选、全选、Esc、批量改优先级、完成和撤销、删除和撤销、批量标签；手机上从菜单进入、点选、批量完成），截图看过。一起拖、拖动分组（列表和看板）、最近7天的空日子有界面测试，拼音排序和搜索有单测，拖动中的样子（多个任务的叠影和数字、看板列的落点线）看过截图。分组方式有单测（各种分组的结果、拖进各种分组改了什么）和界面测试（清单按优先级、标签、时间分组并拖动，添加分组时切回自定义分组；今天按清单分组、拖到别的清单、不分组），电脑 / 手机 / 深色的截图看过。这两轮都没有改表、没有改同步（视图的分组和排序只存本机）。时间线有单测（泳道、无日期、排行、拖右边缘的时长、拖进时间线改日期和分组）和界面测试（电脑上拖动改日期、保留时间、从无日期拖进来、拖回无日期、拖右边缘；分组泳道、换泳道、点空白新建、多选一起拖、切换缩放和今天、折叠泳道、显示已完成；手机上长按拖动、打开无日期），电脑（日 / 周 / 月、深色、没有分组）、手机、拖动中和拖边缘时的截图看过；macOS 正式版能编译，还没在真机上用手拖过。也没有改表和同步（时间线的缩放等设置只存本机）。日历里多选有单测（一起拖时各种情况挪到哪：月格子、全天、小时格，带头的是计时或全天，跨天的任务，已完成 / 删除 / 无日期的不动；Shift 连选的顺序）和界面测试（电脑月视图点选、连选、⌘A、Esc、一起拖、点空白取消、批量完成；周视图一起挪两小时、拖进全天；窄窗口底部操作栏；手机上长按出菜单、点选、批量完成，小时格上长按不动不会挪时间，长按拖动一起挪），电脑浅色 / 深色、拖动中、手机的截图看过；macOS 正式版能编译。没有改表和同步。Android 没有编译过。

代码在 GitHub：`kadaliao/opentodo`（公开，AGPL-3.0）。

## 2. 代码地图

```
app/                          Flutter 客户端
  lib/main.dart               入口：ProviderScope + OpenTodoApp
  lib/data/
    db.dart                   drift 表：TaskLists / Tasks / ChecklistItems / TaskFilters / ListSections（都带同步字段）、KeyValues（本地设置）
    db.g.dart                 drift 生成，别手改
    keys.dart                 KeyValues 的键名
    repo.dart                 TaskRepo：所有写操作的唯一入口（会打 updatedAt / dirty）
  lib/domain/                 纯函数，单测覆盖
    calendar.dart             日历：各模式显示哪些天、哪些任务（含重复任务以后的日期）、重叠任务分列；拖到哪（一个或几个一起：dropTarget / dropTargets）、Shift 连选的顺序
    dates.dart                日历日期工具、中文日期/时间标签、时间段
    filters.dart              过滤器：条件的格式（JSON）、匹配、普通表单、快速添加的默认值
    holidays.dart             法定节假日和调休（每年按国务院通知加一年）
    ordering.dart             手动排序：拖到两个任务之间时算新的 sortOrder（一个或几个一起），挤不下时整组重排
    pinyin.dart               拼音：按标题排序用的键、搜索时按全拼 / 首字母匹配；常见多音字的其他读音
    pinyin_table.dart         每个汉字的拼音表（tool/pinyin_table.swift 生成，别手改）
    lunar.dart                农历换算、月名日名、传统节日（1900–2100 的表）
    quick_add_parser.dart     快速添加解析（日期、时间、重复、#标签、!优先级）
    recurrence.dart           重复规则（RRULE 子集）：解析、下一次日期、中文描述
    reminders.dart            提醒：触发时刻、文案、接下来要交给系统的提醒
    search.dart               搜索：拆词、匹配、排序、要标黄的位置、描述里截一段
    task_defaults.dart        任务默认值（默认提醒、时间段默认时长）
    timeline.dart             时间线：缩放、每个任务的横条（从哪天到哪天）、按分组分泳道、无日期的任务、排行、拖右边缘后的时长
    views.dart                视图（智能清单/清单/标签/过滤器）的筛选、计数；分组方式（TaskGrouping）和排序（TaskSort），每个视图能选哪些；每一组拖进去改什么（GroupTarget）；清单按分组（ListSections）排、看板的列
  lib/notify/
    reminder_backend.dart     交给系统：iOS/macOS/Android 由系统定时，Windows/Linux 用计时器；通知上的按钮；测试里是空实现
    reminder_actions.dart     通知按钮“完成”“稍后提醒”做什么、稍后提醒的存储、后台入口
    reminder_scheduler.dart   和系统里已排上的通知比对，只动变了的
  lib/state/
    providers.dart            数据库流（含过滤器、分组、搜索用的全部子任务）、每个视图的分组和排序、清单用列表、看板还是时间线（ViewPrefs，存本机）、当前模块（任务/日历）、当前视图、选中任务、每分钟刷新的时钟
    calendar_providers.dart   日历的模式和显示选项（存本机）、锚点日期、各范围的条目、这一页的任务顺序（连选、全选用）、拖动时一起走的选中任务
    reminder_providers.dart   提醒调度（ReminderController）、点通知打开任务
    settings_providers.dart   设置（AppSettings，存本机）
    timeline_providers.dart   时间线的缩放、显示已完成、无日期开没开（TimelinePrefs，存本机，所有清单共用）
    sync_providers.dart       账号（AccountNotifier）、同步调度（SyncController）
    selection.dart            多选（TaskSelection）：⌘ / Ctrl 点选、Shift 连选，点任务时该做什么（tapTask）
  lib/sync/
    account.dart              登录接口、错误文案、默认服务器地址
    codec.dart                本地行 ↔ 网络格式（逐字段）
    sync_engine.dart          一次同步、首次登录清理、退出清空
  lib/ui/
    app.dart                  MaterialApp、主题、本地化；挂着同步控制器
    home_shell.dart           模块切换（电脑左侧图标栏、手机底部栏）、搜索和设置入口、⌘F；任务模块的自适应布局（≥1000 三栏，≥640 两栏，否则抽屉）
    calendar/                 日历：calendar_screen（顶栏、侧栏、详情或批量面板、新建框，点任务时的多选）、month_view、time_grid、agenda_view、entry_chip（任务条、拖动，选中的一起拖：CalendarDrag）
    sidebar.dart              侧栏（智能清单、清单、过滤器、标签）；底部 account_ui.dart 的账号/同步状态
    filter_editor.dart        过滤器的新建 / 编辑框（普通、高级）、删除
    board_view.dart           看板：每个分组一列，列里添加任务，已完成折叠在列底
    timeline_view.dart        时间线：无限横向滚动（自己的视口 _EndlessViewport）、日期表头、泳道、横条、拖右边缘、无日期一栏
    task_drag.dart            拖动任务（电脑直接拖，手机长按拖、长按不动出菜单）；拖的是选中的任务时一起拖（DraggedTasks）；放进某一组（GroupDrop：分组、某天、优先级、清单、标签，清单是自定义排序时还看放在哪个位置）；提示线、拖到边上自动滚动；指针抓在哪（taskDragGrab）、哪些任务正被拖（isTaskDragged）
    section_actions.dart      分组的添加、重命名、移动、删除；拖动分组（SectionDraggable / SectionDropTarget）
    batch_actions.dart        多选后的批量操作：宽屏右边的面板（BatchPanel）、窄屏底部的操作栏（BatchBar）、批量标签
    search_panel.dart         搜索框和结果（电脑上是对话框，手机上是一页）；revealTask：切到能看到某个任务的视图并打开它
    task_list_pane.dart       中间列表、分组折叠、空状态
    task_tile.dart            任务行、优先级勾选框
    task_detail.dart          详情（标题、备注、子任务、日期/提醒/重复、优先级、清单）
    quick_add_field.dart      快速添加输入框（高亮识别出的部分）
    task_actions.dart         右键/长按菜单、日期选择、完成（重复任务带撤销）、跳过此次、清单选择
    schedule_dialog.dart      日期对话框：日期 / 时间段、时间、提醒、重复，自定义提醒、自定义重复
    settings_page.dart        设置（电脑上是对话框，手机上是一页）
    dialogs.dart              确认框、清单编辑
    theme.dart                配色（种子色 #14A38B）、优先级颜色、断点
  test/                       单元、界面、同步集成测试
server/                       Go 同步服务
  cmd/opentodo-server/        入口；-backup-dir 是备份命令
  internal/store/store.go     SQLite：用户、会话、记录、Sync()
  internal/api/               HTTP 接口、限流、测试
  deploy/                     systemd 单元、Caddy 片段、deploy.sh
app/tool/lunar_table.swift    生成 lunar.dart 里农历表的脚本（用 macOS 的中国历）
app/tool/pinyin_table.swift   生成 pinyin_table.dart 的脚本（用 macOS 的汉字转拼音）
docs/                         本文、架构、路线图
reference/                    滴答清单截图（gitignore，只在本机）
```

## 3. 开发环境

- **Flutter 3.50 / Dart 3.14**。Flutter SDK 和 pub 缓存（`PUB_CACHE`）都很大，系统盘紧张的话放到别的盘。
- **Xcode**：iOS、macOS。
- **Go 1.27**：服务端；客户端的同步集成测试也要用它编译服务端。
- **Android 还没配过**：需要 Android Studio（或命令行工具）和 JDK，设 `ANDROID_HOME`。

本机特有的环境信息（SDK 装在哪、端口占用、代理之类）写在仓库根目录的 `CLAUDE.local.md`，这个文件不进仓库。

## 4. 常用操作

README 里有基本命令。另外几个：

```sh
# macOS 正式版（日常自己用这个）
cd app && flutter build macos --release
open build/macos/Build/Products/Release/OpenTodo.app

# 装到 iPhone 模拟器
flutter build ios --simulator --debug
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted com.liaoxingyi.opentodo

# 看 Mac 版本地数据库（只读；别打印 account.token）
sqlite3 "file:$HOME/Library/Containers/com.liaoxingyi.opentodo/Data/Library/Application Support/com.liaoxingyi.opentodo/opentodo.sqlite?mode=ro"

# 本地跑服务端（登录框“服务器”里填 http://127.0.0.1:8686）
cd server && go run ./cmd/opentodo-server
```

**每年加节假日安排**：国务院办公厅通常在 11 月发布下一年的《部分节假日安排的通知》（中国政府网、新华网都有全文）。照着在 `app/lib/domain/holidays.dart` 的 `_schedules` 里加一年：每个假期写名字、放假起止（`MM-DD`）和调休上班的日子，注释写上文号；`test/holidays_test.dart` 里加几条这一年的检查（会自动核对调休上班都在周末）。然后发版。没数据的年份，法定工作日按周一到周五算，日历上不标休 / 班。

**拼音表**一般不用动。要重新生成：`swift app/tool/pinyin_table.swift > app/lib/domain/pinyin_table.dart`（在 `app/` 下跑时去掉前缀）。表里每个字只有一个读音；常见多音字的其他读音（银行的“行”、长期的“长”）写在 `pinyin.dart` 的 `_polyphones`，排序用第一个。

**农历表**超出 2100 年时再生成：`swift app/tool/lunar_table.swift` 输出表，替换 `lunar.dart` 里的 `_years`（脚本里的年份范围一起改）。

## 5. 约定和踩过的坑

**Flutter**
- Material 组件从 3.50 起是独立包：一律 `import 'package:material_ui/material_ui.dart'`。中文本地化用 `material_ui` 里的 `GlobalMaterialLocalizations.delegates`。
- 改了 `db.dart` 的表：`schemaVersion` 加一，在 `migration.onUpgrade` 里写迁移步骤，再跑 `dart run build_runner build`。已经发出去的版本里有用户数据，不能靠删库重建。
- 界面测试里不要 `close()` drift 的内存数据库，也不要在 `tester.runAsync` 里关：它等的是模拟时钟里排队的操作，测试会一直卡住。
- drift 生成的数据类、Dart 的 record 里装着 List 时，`==` 比的是引用。测试里比较要转成 JSON 或字符串再比。
- 示例数据（欢迎清单）用固定 ID（`seed-welcome`、`seed-welcome-1..3`、`seed-today`），多设备才不会重复。别改回随机 ID。重复任务完成后留下的副本也是同样的道理，ID 由任务 ID 和日期算出（见 architecture.md）。
- drift 的 `insertOnConflictUpdate` 传数据类时，值为 null 的字段会被当成“不更新”。要把字段写回 null（比如让带删除标记的行复活），传 `xxx.toCompanion(false)`。

**提醒和通知**
- 插件是 `flutter_local_notifications`。iOS 要在 `AppDelegate` 里设 `UNUserNotificationCenter.current().delegate`（已加），macOS 插件自己设。Android 要 compileSdk 37、core library desugaring、清单里的权限和两个 receiver（都已按插件文档加上，但还没编译过）。
- 界面测试里 `reminderBackendProvider` 默认是空实现（检测到 `FLUTTER_TEST`）。要验证调度，像 `test/app_test.dart` 那样换成 `FakeBackend`。
- 系统最多替应用保留 64 个待发通知，所以只排最近的 48 个，剩下的靠应用运行时补。
- 通知按钮在 iOS / Android 上由插件另起的后台引擎处理（`reminderActionInBackground`，必须是带 `@pragma('vm:entry-point')` 的顶层函数）。iOS 的 `AppDelegate` 里要 `FlutterLocalNotificationsPlugin.setPluginRegistrantCallback`，后台引擎才有插件可用（已加）。macOS 插件不支持后台 isolate，按钮总是交给应用。
- 改了交给系统的通知的样子（按钮、分类、频道），把 `_reminderFormat` 加一，已经排上的老通知才会被换掉。

**同步（改之前先读 architecture.md 的同步一节）**
- 加字段：`codec.dart` 的 `xxxToWire` 和 `wireToXxx` 两边都加，读的一侧给默认值，旧客户端才不会因为新字段出错。
- 同步引擎必须**先应用拉回的记录，再标记推送成功**。顺序反了会让旧记录盖掉刚推上去的新改动；集成测试 `the newer edit wins a conflict` 专门盯着这一点。
- 新者胜是按设备时钟比较的，设备时间不准会判错，以后要换成混合逻辑时钟（HLC）。
- 新加一种要同步的数据（比如习惯）：服务端 `store.Entities` 白名单里加上它的名字，**先部署服务端再发客户端**（旧服务端见到不认识的类型会拒掉整个请求，客户端就完全同步不了）；客户端 `sync_engine.dart` 里 `_dirty`、`_markAccepted`、`_apply`、`_purgeSyncedTombstones`、`watchDirtyCount`、`clearLocalData` 都要加；加表的那次迁移把 `sync.cursor` 归零（旧版本跳过了别的设备同步上来的这种记录，游标却已经走过去了，不归零就永远拉不到）。过滤器（v5）是照这个做的。
- iOS 应用切到后台时定时器会暂停，回到前台才同步（有 `AppLifecycleListener` 兜底）。
- 同步集成测试每个用例都重新登录，超过服务端默认的每分钟 10 次登录限流，所以测试启动服务端时带 `-auth-per-minute 1000`。

**界面验证**
- 优先用界面测试（`test/app_test.dart` 的写法）。用模拟点击和键盘去操作真实应用时，先确认目标窗口在前台，否则按键会落进别的窗口。
- 日历的拖动在手机平台上是长按拖，而测试默认按 Android 跑。测电脑上的直接拖动，像 `test/calendar_ui_test.dart` 那样加 `variant: TargetPlatformVariant.only(TargetPlatform.macOS)`。
- 拖动时浮在上面的那份（`feedback`）在 Overlay 里，不在 `Material` 下面，没有文字样式：里面有自己的 `Text` 时外面包一层 `Material`（透明的就行），否则测试里显示成方块、真机上带黄色下划线。测试里阴影画成粗黑框，是测试的画法，不是问题。
- 拖动的放置目标（`DragTarget` 的 builder）在有没有东西悬停时，包在外面的组件结构要一样：比如 `Container` 有没有 `foregroundDecoration` 会多一层或少一层，被拖的那一行就被重建，拖动结束的回调丢掉（手机上长按不动不出菜单就是这样查出来的）。用一直存在的 `DecoratedBox`，只换装饰。
- 手机上长按不动松手也算一次“放下”：放置目标的 `onAccept` 照样会来，而且在拖动方的 `onDragEnd` 之前。日历的小时格放下时按 15 分钟取整，不拦的话 9:10 的任务长按一下就变成 9:00。所以日历的放置目标先问 `droppedInPlace`（拖动副本离起点不到 8 像素就当没动）。
- 放置目标想知道指针在哪：`Draggable` 的 `onDragUpdate` 在各个 `DragTarget` 的 `onMove` 之后才调，用它记指针总是慢一步。改用 `taskDragGrab`（按下时指针在被拖那一行里的位置）加上 `onMove` 给的拖动副本左上角。时间线就是这样让抓住的那一天留在指针下面的。
- 只画屏幕上看得见的东西时，正被拖的那个也要留着（`isTaskDragged`）：拖到边上自动滚动会把它滚出屏幕，`Draggable` 被拆掉后 `onDragEnd` 不会再来，拖动状态就清不掉。
- 时间线的横向滚动是一个普通的 `Scrollable` 配自己的视口（`_EndlessViewport`：布局时告诉滚动位置左右各能滚十年，内容按 `offset.pixels` 现画）。这样触控板、Shift+滚轮、惯性和拖到边上自动滚动（`EdgeDraggingAutoScroller`）都是现成的。电脑上鼠标拖不动 `Scrollable`（Flutter 默认只让触屏和触控板拖），所以表头另外接了鼠标拖动。
- 想看某个界面长什么样又不想去点真实应用：写一个临时测试，用 `FontLoader` 把系统里带中文的字体（macOS 的 `/Library/Fonts/Arial Unicode.ttf`）注册成 `Roboto`（测试按 macOS 跑时界面用的是 `.AppleSystemUIFont`，也注册一份），把 Flutter SDK 里的 `bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf` 注册成 `MaterialIcons`，应用外面包一层 `RepaintBoundary`，用 `captureImage` 存成 PNG。emoji 显示不出来，其余和真机一致。看完删掉这个测试。

## 6. 部署和运维

同步服务部署在一台带 systemd 的 Linux 服务器上，前面用 Caddy 反向代理并自动签 HTTPS 证书。官方服务的地址是 `https://todo.liaoxingyi.com`；服务器的具体信息在 `CLAUDE.local.md`（不进仓库）。

| 项 | 内容 |
|---|---|
| 程序 | `/opt/opentodo/opentodo-server`，systemd 服务 `opentodo.service`，专用用户 `opentodo`，只监听 `127.0.0.1:8686` |
| 数据 | `/var/lib/opentodo/opentodo.db`（SQLite，WAL 模式） |
| 备份 | `opentodo-backup.timer` 每天约 4:30 写到 `/var/lib/opentodo/backups/`，留 14 份 |
| 反代 | Caddy 站点配置见 `server/deploy/Caddyfile.snippet` |

- 第一次部署：DNS 指向服务器，把 `Caddyfile.snippet` 加进服务器的 Caddyfile 并重载 Caddy，然后在 `server/` 下运行 `OPENTODO_HOST=<ssh 主机> ./deploy/deploy.sh --setup`（建用户和目录、装 systemd 单元）。
- 之后更新：`OPENTODO_HOST=<ssh 主机> ./deploy/deploy.sh`（交叉编译、上传、重启、等健康检查）。
- 看日志：`ssh <主机> sudo journalctl -u opentodo -f`。
- 从备份恢复：
  ```sh
  sudo systemctl stop opentodo
  sudo -u opentodo cp /var/lib/opentodo/backups/opentodo-<时间>.db /var/lib/opentodo/opentodo.db
  sudo rm -f /var/lib/opentodo/opentodo.db-wal /var/lib/opentodo/opentodo.db-shm
  sudo systemctl start opentodo
  ```
  恢复后各设备的 cursor 可能比服务器新，目前没有自动处理；要让客户端退出重登，从头同步。

## 7. 已知问题和技术债

- 登录令牌存在本地数据库，没进系统钥匙串。
- 注册对任何人开放，没有邮箱验证、找回密码。限流只有登录注册（每 IP 每分钟 10 次），同步接口没有。
- 冲突按设备时钟“新者胜”（见上）。
- 整行“新者胜”的副作用：比这个版本旧的客户端改了任务，推上去的数据里没有它不认识的字段（M4 的提醒和重复、之后的时间段 `duration`），会把别的设备上的这些设置清掉。所有设备都要升级到最新版本。以后可以让客户端原样保留不认识的字段。
- 任务在别的设备上完成或删除后，这台设备要等应用运行、同步之后才会取消它的提醒；应用一直没开的话，到点仍会弹。
- 节假日数据靠每年手动加、发版；用户不升级就没有新一年的休 / 班，法定工作日重复会退回按周一到周五算。以后可以改成由同步服务下发。
- 农历重复和法定工作日写进 `repeatRule` 的 `RSCALE`、`X-HOLIDAYS` 旧版本不认识：旧版本把农历规则当成无效（不重复），把法定工作日当成普通工作日；它完成一次后写回的规则会丢掉这些部分。要彻底解决得有服务端推送。
- 服务器恢复备份后，客户端的 cursor 不会自动回退。
- iOS 的 `Info.plist` 为了开发放行了本地 HTTP（`NSAllowsLocalNetworking`），上架前评估是否去掉。
- 应用图标还是 Flutter 默认的。
- 没有 CI。
- macOS 正式版是本机临时签名，发给别人用需要开发者证书签名和公证。

## 8. 下一步（建议顺序）

每项都可以对照 `reference/dida-app/` 里的截图做，索引见那里的 README。

1. **清单的后续**：时间线可以加：拖左边缘改开始日期、今天 / 标签 / 过滤器也能用时间线、手机上改结束日期（现在只有电脑上能拖右边缘）。搜索可以加最近搜索、在描述里也用拼音找；过滤器可以加拖动排序、在日历里按过滤器筛、日期的自定义范围。
2. **M4 遗留的验证和小项**：通知按钮在 iPhone 真机上按一遍（应用开着、在后台、被杀掉三种情况）；设置现在只存本机，以后可以做成同步的；Windows 的通知还没加按钮；艾宾浩斯记忆法重复；每年 11 月加下一年的节假日（见第 4 节）。
3. **Android 环境**：装工具链，跑通 `flutter build apk`，真机试一遍同步和提醒（Android 14+ 的精确闹钟权限默认没给，没给时提醒可能晚几分钟）。
4. **账号完善**：找回密码、邮箱验证、Apple 登录；令牌改存钥匙串（`flutter_secure_storage`）。
5. **电脑端小组件（M6）**：菜单栏小窗、全局快捷键快速添加、桌面便签。用 `window_manager`、`tray_manager`、`hotkey_manager`、`desktop_multi_window`；多窗口共享数据开 drift 的 `shareAcrossIsolates`。参考 `70*`、`71`、`81`。手机桌面小组件要写原生代码（SwiftUI WidgetKit、Android Glance），可以用 `home_widget` 传数据。
6. **效率模块（M5）**：番茄专注、习惯打卡、倒数日、四象限。参考 `65`–`68`。做成新模块：在 `home_shell.dart` 的 `_modules` 和 `AppModule` 里加一项。
7. **日历补充**：“安排任务”面板（把没日期的任务拖进日历，参考 `43`）、年视图和多周、点任务弹出卡片（参考 `45`，现在是右侧详情）、月视图里跨天的任务画成一整条（现在是每天一个）。

还没定、需要用户拍板的：应用图标和配色。

## 9. 参考资料

- `reference/dida-app/`：滴答清单 Mac 版 8.2.50 的 109 张界面截图，按功能编号，`README.md` 是索引。
- `reference/dida-official/`：官网宣传图。
- 这些图只作内部参考：滴答的名字、图标、插画、文案都不能进产品。
