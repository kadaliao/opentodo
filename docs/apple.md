# Swift 原生版（苹果平台）

2026-11-26 起，苹果平台（macOS、iOS）的客户端改用 Swift 原生重写，代码在 `apple/`。Flutter 版（`app/`）留在仓库里：它是这次重写的**规格**（每个功能照它的行为做，测试照它的测试移植），以后做别的平台时也还要用。服务端（`server/`）和同步协议不变，两个客户端可以同时连同一个账号。

为什么重写：Flutter 画出来的界面不像苹果自己的应用。所以这一版的界面原则是**用系统自带的东西**，看起来、用起来像系统自带的提醒事项和日历，而不是把 Material 的布局搬过来。功能和数据逻辑照 Flutter 版，界面按苹果的习惯重新设计。

## 1. 目录

```
apple/
  project.yml               XcodeGen 的工程描述；OpenTodo.xcodeproj 是生成的，不进仓库
  App/                      应用外壳：@main、Info.plist、图标、entitlements、App Shortcuts（很薄，逻辑都在包里）
  Widgets/  ShareExtension/ 小组件扩展、分享扩展（第 9 节）
  Intents/                  App Intents，应用和小组件扩展都编进去
  Extensions/               扩展的 entitlements
  OpenTodoKit/              Swift 包，四个库
    Sources/OpenTodoDomain/ 纯逻辑，只依赖 Foundation：数据模型（Models.swift）、Day / LocalDateTime（Day.swift）、
                            日期工具（Dates.swift）、农历、节假日、重复、提醒、快速添加、过滤器、搜索、视图分组、排序、日历、时间线
    Sources/OpenTodoData/   GRDB（SQLite）：数据库和迁移、TaskRepo / EfficiencyRepo（所有写操作的入口）、TaskData（界面读的快照）、
                            本机设置、同步（codec / 引擎 / 账号 / SyncController）、提醒调度、AppServices（启动器）
    Sources/OpenTodoUI/     SwiftUI，按功能分目录（第 7 节）：App/（根视图、DebugLaunch、Snapshot）、Model/（AppModel 和子模型）、
                            Shell/（外壳、对话框、菜单命令）、Components/、Tasks/、Schedule/、Batch/、Search/、Filters/、
                            Board/、Drag/、Timeline/、Calendar/、Efficiency/、Settings/、Account/、System/
    Sources/OpenTodoSystem/ 应用和扩展共用的系统集成部分：应用链接、小组件内容、扩展写库、分享转任务、全局快捷键的值
    Tests/                  每个库一个测试目标（Swift Testing）：OpenTodoDomainTests / OpenTodoDataTests / OpenTodoUITests / OpenTodoSystemTests
  UITestsIOS/               iOS 的 XCUITest（在模拟器里点界面）
  scripts/                  generate.sh、build.sh、shot.sh（还有 shot.sh 用的 windowid.swift）、make_icon.swift（应用图标）、release.sh（发布，第 9 节）
  .derived/                 build.sh 的 DerivedData 和日志，不进仓库
```

对应关系：`app/lib/domain/*.dart` → `OpenTodoDomain`；`app/lib/data`、`app/lib/sync`、`app/lib/notify` 里和界面无关的部分 → `OpenTodoData`；`app/lib/state`、`app/lib/ui` → `OpenTodoUI`。移植时文件名跟着 Dart 的走（`recurrence.dart` → `Recurrence.swift`），好对照。

## 2. 技术选择

- **Swift 6 语言模式**，严格并发检查。最低系统 **macOS 26 / iOS 26**，用 Xcode 27 编。包是 `swift-tools-version: 6.2`；所有目标开了 `NonisolatedNonsendingByDefault` 和 `InferIsolatedConformances`，`OpenTodoUI`（和它的测试）默认隔离在 `MainActor`（`defaultIsolation`），Domain 和 Data 不是。
- - 模拟器的命令都加超时（`perl -e 'alarm 120; exec @ARGV' xcrun simctl …`），一次只跑一条。几个模拟器同时开、再加上编译时，机器负载上到几百到上千，`simctl boot` 停在 Booting、`launch` / `io screenshot` / `shutdown` 都不返回；只开一个、别人不编译时，boot 6 秒、launch 和截图各 10 秒左右。
- `coreaudiod` 会被不停发声的进程（比如终端的音效插件）拖垮：攒下几千个线程、几百个没释放的防休眠占用（`pmset -g assertions` 能看到），负载数字从此降不下来，模拟器启动越来越慢；占用满了以后 `xcodebuild test` 直接报 “Failed to prevent system sleep during UI testing”，界面测试跑不起来。关掉那个插件不够，要 `sudo killall coreaudiod`（系统会自己重启它）。
- 新建的模拟器第一次弹出键盘会盖一层“滑动输入”的教程，截图里键盘位置全被挡住。新建后先写 `xcrun simctl spawn <udid> defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true`，再重启一次模拟器。
- 想看应用里的值又截不到时，在代码里临时 `NSLog("%@", "QADBG …")`，跑完用 `xcrun simctl spawn <udid> log show --last 30s --predicate 'process == "OpenTodo"'` 读（`print` 在 `simctl launch --console` 下有缓冲，被杀掉时什么也看不到），看完删掉。

**SwiftUI**，一个多平台应用目标（macOS + iOS）。只在 SwiftUI 做不到时才用 AppKit / UIKit，包在很小的桥接里。
- **GRDB 7**（SwiftPM 从 github.com/groue/GRDB.swift 取，`Package.resolved` 进仓库）读写 SQLite。界面用 `ValueObservation` 订阅数据库。
- **XcodeGen** 生成工程：改 `project.yml`，不手改工程文件。
- **Swift Testing**（`import Testing`）写测试。
- 界面文字直接写中文（开发语言 zh-Hans），和 Flutter 版一样，暂不做多语言。
- 不引入别的第三方库，除非先在本文档里写明理由。

## 3. 数据和兼容（不能破坏的约定）

- **数据库结构和 Flutter 版（drift，schema 7）完全一样**：表名、列名、类型、默认值都照 `app/lib/data/db.dart` 生成的结果（`task_lists`、`tasks`、`checklist_items`、`task_filters`、`list_sections`、`key_values`，列名是下划线小写）。正式版和 Flutter 版用同一个包名 `com.liaoxingyi.opentodo`，装上 Swift 版直接接着用原来的数据：数据库现在放在 App Group 容器里（应用和扩展共用，第 9 节），第一次启动时把 Flutter 版位置（macOS：`Application Support/com.liaoxingyi.opentodo/opentodo.sqlite`；iOS：`Library/Application Support/opentodo.sqlite`）的库复制进去，老文件留着；Swift 版第一次打开 Flutter 的库时还会在旁边留一份 `opentodo.sqlite.before-swift`。
- 版本号继续用 `PRAGMA user_version`：7 及以前是 Flutter 版的迁移（Swift 版也要能从 1–6 升上来，照 `db.dart` 的 `onUpgrade`），8 起是 Swift 版加的。加表、加列的规矩和以前一样：版本加一、写迁移、不能删库重建。
- **`key_values` 里的 JSON 格式也照旧**（设置、每个视图的分组和排序、日历和时间线的选项、稍后提醒、种子数据 ID），键名见 `app/lib/data/keys.dart`。读不出来或字段不认识时用默认值。
- **同步的网络格式逐字段照 `app/lib/sync/codec.dart`**，读的一侧给默认值。同步引擎先应用拉回的记录、再标记推送成功。新加一种要同步的数据时，先部署服务端。
- **调试版用另一个包名 `com.liaoxingyi.opentodo.dev`**，碰不到正式数据。测试和截图用的数据库放临时目录。
- 模型类型放在 `OpenTodoDomain/Models.swift`（纯结构体，`Sendable`、`Hashable`、`Codable`、`Identifiable`）：`TodoTask`（不叫 `Task`，避开并发库的 `Task`）、`TaskList`、`ChecklistItem`、`ListSection`、`TaskFilter`，还有 `inboxListId`。字段名就是 Dart 的驼峰名；时间戳是毫秒 `Int`，`sortOrder` 是 `Double`，`tags` 是 `[String]`，`reminders` 是 `[Int]`，`TodoTask.dueDate` 是 `Day?`；`status` / `priority` / `repeatFrom` 是 `TaskStatus` / `Priority` / `RepeatFrom` 枚举（原始值和 Dart 的数字一样，读到不认识的数字回落到默认值）。每个初始化方法的参数都有默认值，测试只写关心的字段。GRDB 的读写协议在 `OpenTodoData` 里用扩展加。
- 日期（`Day.swift` 文件头有完整用法）：`Day` 是纯的日历日期（存儒略日，对应数据库里的 `YYYY-MM-DD`），`LocalDateTime` 是 `Day` 加当天的分钟数，都不带时区，算术全是整数，结果不随机器时区变。Dart 里表示日期或“墙上时间”的本地 `DateTime` 分别对应这两个；`DateTime(y, m, d, 0, 分钟)` 那种越界进位用 `Day(y, m, d)` / `LocalDateTime(day, minute:)` 照样进位。只有和 `Date` 互转（`Day(date, in:)`、`Day.today(in:now:)`、`LocalDateTime.now(in:now:)`、`.date(in:)`）才带 `TimeZone`，默认当前时区。“现在”由调用方传进纯函数，和 Dart 版传 `now` 一样，测试才能固定时间。`Dates.swift` 是 `dates.dart` 的移植，函数名照旧（`dateKey` → `day.key`、`daysBetween(a, b)` → `a.days(to: b)` 这类对照写在文件头）。
- Swift 版新加的本机数据和格式：最近搜索存在 `key_values` 的 `search.recent`（JSON 字符串数组，最新的在前，最多 10 条，不同步；`RecentSearches`）。过滤器日期条件的“自定义范围”作为日期条件的一个值存成 `"2026-11-01~2026-11-30"`（`FilterDateRange`）：Flutter 版遇到不认识的日期值时匹配时跳过、编辑框里原样显示、保存时原样写回，所以旧版本不会出错，只是不按这个范围筛。
- 登录令牌存系统钥匙串（Flutter 版存在 `key_values` 的 `account.token`，第一次启动时搬过去并从库里删掉）。

## 4. 界面原则

- 像系统应用：macOS 用 `NavigationSplitView`（侧栏 / 列表 / 详情）、工具栏、菜单栏命令和快捷键、设置窗口、右键菜单；iOS 用 `TabView` + `NavigationStack`、半屏 sheet、滑动操作、长按菜单。控件、间距、字体、图标（SF Symbols）、材质都用系统默认的，不自己画一套。
- **界面大小**（macOS，设置 → 通用，显示菜单 ⌘+ / ⌘- / ⌘0）：小 / 标准 / 大 / 特大，存在本机 UserDefaults（`InterfacePrefs`）。macOS 的系统文字样式不跟 `.dynamicTypeSize` 变，`@ScaledMetric` 也不变，所以缩放是一个环境值 `uiScale`，只在每个窗口的根上由 `.interfaceScaleRoot()` 设一次（主窗口、设置窗口、菜单栏小窗、快速添加面板；同时设默认字体、控件大小、侧栏行高）。写界面照这个约定，就会跟着变（`Components/InterfaceScale.swift` 文件头有例子）：
  - 字体用 `.uiFont(.body)`、`.uiFont(.caption, weight: .semibold)`、`.uiFont(size: 11)`，不用 `.font(…)`；要 `Font` 值（`Text` 里拼 `Text`、Canvas）用 `Font.ui(.caption, scale: s)`。没写字体的文字跟根上的默认字体走。
  - 写死的尺寸（frame、padding、spacing、圆角、图标框、行高）乘 `@Environment(\.uiScale) private var s`：`.frame(width: 16 * s)`；存起来的尺寸可以用 `@UIScaled private var box: CGFloat = 16`。窗口最小尺寸、分栏的最小宽度、日历每小时的高度、时间线的行高和每天的宽度不乘。
  - 系统自己定字体的文字（`Section` 的 header / footer、侧栏分组标题）加 `.uiDefaultFont(.headline)` 之类：标准档什么都不做，别的档给一个跟着变的字体（否则会变成和行一样大）。
  - 标准档时这些帮手返回的就是原来的字体和尺寸，根上什么都不设，所以默认外观一个像素都不变；iOS 上 `uiScale` 恒为 1，照旧跟系统的动态字体走。
- 深色模式、动态字体、VoiceOver 标签要正常。强调色是 `#14A38B`（Assets 里的 AccentColor），优先级颜色照 `app/lib/ui/theme.dart`。
- 状态放在 `@Observable` 的模型里（`AppModel` 经 `.environment` 传下去），视图里不直接碰数据库；写操作都走 `TaskRepo`。
- 竞品截图在 `reference/dida-app/`（不进仓库；用 worktree 时它只在主工作区里，位置见 `CLAUDE.local.md`），只看功能怎么组织；名字、图标、文案、配色不能用。
- 调试入口（只在调试版里，应用外壳用 `#if DEBUG` 把 `DebugLaunch.current` 传给 `RootView`）：`-OTDatabasePath <文件>` 指定数据库（这时通知放内存、令牌放库里、不注册全局快捷键）、`-OTSeed demo` 填演示数据、`-OTOpen <路由>` 直接打开某个界面、`-OTAppearance light|dark`、`-OTQuickAdd <文字>` 预填快速添加、`-OTInterfaceSize small|standard|large|extraLarge`（macOS）这次运行用的界面大小（不管存的是什么）、`-OTHiddenWindows yes`（macOS）窗口都放到桌面后面（第 5 节）、`-OTSnapshot <png>`（macOS）窗口出来、数据到了以后自己画成 PNG 再退出。路由（`smart:today`、`list:<id>`、`task:<id>`、`calendar:month`，各功能的演示路由）的完整列表在 `OpenTodoUI/App/DebugLaunch.swift` 文件头。macOS 版开了沙盒，只能写自己的容器，所以文件参数写相对路径时落在应用的临时目录（`~/Library/Containers/com.liaoxingyi.opentodo.dev/Data/tmp/`），脚本都这么传。

## 5. 怎么验证

```sh
cd apple/OpenTodoKit && swift build && swift test      # 领域、数据、系统集成、界面模型四组（同步集成测试会编译并启动 server/ 里的 Go 服务）
cd apple && ./scripts/generate.sh                      # 生成 OpenTodo.xcodeproj（build.sh 也会先跑它）
./scripts/build.sh macos                               # 编 macOS 调试版 → .derived/Build/Products/Debug/OpenTodo.app
./scripts/build.sh ios                                 # 编 iOS 模拟器调试版 → .derived/Build/Products/Debug-iphonesimulator/
./scripts/shot.sh ios <模拟器名> <路由> <输出.png>       # 编、装到模拟器（没有这个名字就新建）、按路由打开、等画面不再变、截图
./scripts/shot.sh macos <路由> <输出.png>               # 编、启动 macOS 调试版（临时数据库）、截窗口后退出
```

- 脚本按自己所在的位置找路径，在哪个 worktree 里都能原样用。build.sh 失败时只打印错误，完整日志在 `.derived/build-<平台>.log`。
- shot.sh 的环境变量：`OT_NO_BUILD=1` 不重新编；`OT_INTERFACE_SIZE=large` 界面大小（macOS，经 `-OTInterfaceSize`）；`OT_APPEARANCE=dark` 深色；`OT_SEED=` 不填演示数据（默认 `demo`）；`OT_QUICKADD=<文字>` 预填快速添加；`OT_SIM_TYPE` 新建模拟器的机型（默认 iPhone 18 Pro）。iOS 截图会把状态栏固定成 9:41、满电，模拟器截完不关。macOS 另有 `OT_WINDOW_SIZE=760x460` 窗口内容尺寸（默认 1180x760，经 `-OTWindowSize`，不用上次记住的大小）；`OT_MAC_METHOD=app` 用 ScreenCaptureKit 截应用自己的全部窗口，popover 和 sheet 叠在窗口上一起截出来（`OT_SHOT_WINDOW=settings` 截设置窗口，配 `settings:<页>` 路由：general / tasks / notifications / focus / quickAdd / account / about）。
- macOS 截图有两种办法（`OT_MAC_METHOD`）：`window` 是 `screencapture -l<窗口号>`，要终端有“屏幕录制”权限，截出来和屏幕上一模一样（窗口不在前台，所以红绿灯是灰的）；`self` 是应用自己用 `-OTSnapshot` 把窗口画成 PNG，不要权限，但 AppKit 画不出 Liquid Glass 之类的材质，`NavigationSplitView` 的侧栏一整栏是空白。不指定时脚本先问系统有没有权限（`CGPreflightScreenCaptureAccess`），有就用 `window`，没有就退回 `self`。两种办法的限制见第 10 节。
- macOS 调试版用 `open -g -n -F` 在后台启动（不抢前台、不恢复旧窗口），截完自动退出。脚本默认还带 `-OTHiddenWindows yes`：调试版的每个窗口（主窗口、设置、弹出框、sheet、面板）一出来就放到桌面图片下面一层（`DebugHiddenWindows`，交换了 `NSWindow.order(_:relativeTo:)`），用户看不见窗口开开关关，`screencapture -l` 和 ScreenCaptureKit 照样截得到。要看得见就 `OT_VISIBLE=1`。放到所有屏幕之外不行：窗口能挪出去，但两种截图方法都截不到（“could not create image from window”、SCStream -3811）。`OT_MAC_METHOD=app` 现在逐个窗口截（`desktopIndependentWindow`）再按位置叠起来；弹出框这样截，顶上的玻璃底会画成整个窗口的缩略图，要看弹出框用 `OT_VISIBLE=1`。
- 经 ssh 登进来的会话（比如 herdr 远程连回本机）没有“屏幕录制”权限，`screencapture -l` 报 “could not create image from window”，脚本退回自绘；登录钥匙串在那种会话里也可能锁着，codesign 报 errSecInternalComponent，这时用 `OT_UNSIGNED=1 ./scripts/build.sh macos` 编不签名的调试版（没有沙盒和 App Group，带 `-OTDatabasePath` 的截图和自检够用）。真窗口截图要在本机终端（有屏幕录制权限的那个应用）里跑。
- 脚本启动的窗口会排到别的窗口后面（`-OTWindowSize` 时，`DebugWindowSizer`），不挡用户正在用的窗口；用户在全屏应用里时它开在桌面那个空间，`screencapture -l` 照样截得到（`windowid` 也找别的空间里的窗口），但 `OT_MAC_METHOD=app`（ScreenCaptureKit）截不到，popover 和设置窗口要等用户回到桌面再截。屏幕锁着时什么都截不到（“could not create image from window”），要等解锁；判断锁屏看 `CGSessionCopyCurrentDictionary()` 的 `CGSSessionScreenIsLocked`。

- Flutter 版的每个单元测试都要有对应的 Swift 测试（测试名和用例照搬），这是“行为一样”的凭据。
- 界面改动要看截图：浅色、深色，手机和电脑。截图放 `apple/.shots/`（不进仓库）。
- 别用模拟键盘鼠标去点真实窗口（会落进用户正在用的别的窗口）。要点界面，用模拟器里的 XCUITest，或者用 `-OTOpen` 直接打开那个状态再截图。
- Mac 上要验证点了会怎样：用辅助功能接口操作藏在桌面后面的调试版窗口（选中列表行 `AXSelectedRows`、按按钮 `AXPress`、往输入框填字 `AXValue`），再读界面结构看结果，不碰真鼠标键盘。它不经过鼠标事件，单击被拦掉这类问题（第 10 节）查不出来；那种要在一个小程序里把视图放进窗口、在进程里合成点击：`NSApplication` 子类的 `isActive` 返回 true，窗口子类的 `isKeyWindow` / `isMainWindow` 返回 true，先 `makeKey()`，再 `postEvent` 按下和抬起（再去改 `NSApp.keyWindow` 反而一点都点不中）。终端没有“屏幕录制”权限时也只能这样看。
- iOS 的界面测试（XCUITest）在工程的 `OpenTodoUITestsIOS` 目标里，代码在 `apple/UITestsIOS/<功能>/`，只放非手指不可的（拖动、长按、滑动），能在 AppModel 上说清的放包里的测试。用 `XCUIApplication.launchOpenTodo(route:)` 启动（新的临时库、`-OTSeed demo`、`-OTOpen` 路由），怎么加、怎么跑见 `UITestsIOS/Support/LaunchOpenTodo.swift`。
- 几个人（agent）同时干活时各用各的 git worktree。**同一时间最多一个人开 iOS 模拟器**（名字 `OT-<自己的名字>`，不动别人的），其余只跑 `build.sh ios`；七个模拟器同时开把机器拖垮过（第 10 节）。

## 6. 做到哪了

| 阶段 | 状态 | 内容 |
|---|---|---|
| 基础 | 完成 | 包和工程骨架、模型、`Day` 和日期工具、编译和截图脚本、应用图标 |
| 领域层 | 完成 | `app/lib/domain` 全部移植，测试照搬；另加艾宾浩斯重复、年视图 / 多周 / 跨天条的排布、效率模块的逻辑 |
| 数据和同步 | 完成 | 数据库（schema 8）、迁移、TaskRepo、EfficiencyRepo、本机设置、同步、钥匙串、提醒调度、AppServices；同步集成测试对着真实 Go 服务跑 |
| 界面 | 完成 | 任务模块（侧栏、列表、快速添加、详情、菜单、多选和批量）、日期对话框、看板、时间线、日历、搜索和过滤器、效率模块、设置和账号，都接在真实数据上（第 7、8 节） |
| 系统集成 | 完成 | App Group、小组件、菜单栏小窗、全局快捷键快速添加、分享扩展、快捷指令、Spotlight（第 9 节） |
| 验收 | 模拟器和 Mac 真窗口都逐屏看过，真机还没看 | 和 Flutter 版逐项对照的结果在 [apple-parity.md](apple-parity.md)（“还没补的”“待确认”）。2026-11-26 在 iPhone 17 和 iPad Air 13 寸模拟器上，用演示数据和 `-OTOpen` 路由把主要界面逐屏截了浅色、深色（iPhone 另抽查了最大的动态字体），修了这几类问题：启动路由丢失（种子数据没写完就交出空快照）、内容被导航栏压住（时间线）、标题被别的视图的标题顶掉（日历）、窄屏挤在一起（周视图日期头；窄屏不再提供周和多周）、功能入口看不见（效率模块的切换菜单）、看起来像不能点（过滤器的菜单和选中状态）、popover 太矮（iPad 日期对话框）。同一天收尾时在 Mac 上用 `screencapture -l` 截了集成后的真窗口（任务三栏、清单分组、详情、多选和批量面板、看板、时间线、搜索、过滤器、日期对话框、日历七种视图和卡片、效率四个模块、设置各页、账号、菜单栏小窗和快速添加面板；浅色、深色，1180 宽为主、760 宽抽查），又修了：侧栏的账号行和列表叠在一起、搜索按钮位置、没开详情也显示“关闭详情”、选中行绿底绿字、效率模块的次要按钮挤在工具栏中间、时间线常常打开在十年前、窗口 760 宽时三栏互相压住、窄窗口日历的工具栏全收进 »、批量面板的图标风格；iPad 深色过了一遍。iOS 界面冒烟测试（[development.md](development.md) 第 7 节）跑通。还没做的：真机（通知按钮、手势）和 apple-parity.md 的 8 行待确认 |

## 7. 界面结构和共用组件

代码在 `apple/OpenTodoKit/Sources/OpenTodoUI/`，外壳和任务模块在前几个目录，其余每个功能一个目录：

```
App/         RootView（窗口的根）、DebugLaunch、Snapshot
Model/       AppModel（核心）和它的子模型：SelectionModel、Notices、Presentation、SearchState、TaskListState；
             AppModel+Actions（带提示 / 撤销 / 确认的写操作）、AppModel+Batch（多选和批量）、
             AppLaunch（AppServices 和窗口的模型）、AppModule、DemoData
Shell/       外壳：MacShell（Mac 的窗口：一个侧栏加右边的内容）、ModuleScreen / TasksScreen（iOS 的标签）、CalendarScreen、DialogHost（应用的对话框）、
             NoticeBanner（撤销提示）、QuickAddSheet、SettingsView（包一层 Settings/ 的设置界面）、AppCommands（菜单栏）、
             WindowRestoration
Components/  共用组件（下面的表）
Tasks/       任务模块：ViewsList（侧栏 / 手机首页）、TaskListArea（列表区域：布局切换、标题、工具栏、显示选项）、
             TaskListView、TaskListPicking（多选）、QuickAddField、TaskMenu（右键菜单 / 滑动）、TaskDetailView
Schedule/    日期对话框            Batch/      批量操作（面板、操作栏）
Search/      搜索（macOS 浮层、iOS 标签页；SearchApp 接进 AppModel）
Filters/     过滤器编辑器、可单独嵌入的规则编辑器
Board/ Drag/ 看板、列表和看板的拖动    Timeline/   时间线（TaskTimeline 接进列表区域）
Calendar/    日历（CalendarWiring 接进 AppModel）    Efficiency/ 四象限、专注、习惯、倒数日（Efficiency/App 接进应用）
Settings/ Account/  设置的各页、账号和登录         System/     菜单栏窗口、全局快速添加（第 9 节）
```

### 窗口的结构

- **模块**：任务、日历、四象限、专注、习惯、倒数日（`AppModule`，这个顺序）。
- **macOS**（`Shell/MacShell.swift`）：整个窗口**只有一个侧栏**，不管右边显示什么它都不变：最上面是“搜索”（样子像搜索框，点了打开浮在窗口上的搜索，⌘F，任何模块都能用）；智能清单；日历、四象限、专注、习惯、倒数日各占一行，带图标和名字，行尾一个词说近况（习惯 `2/5`、`专注中`、有倒数日到了写“今天”；`moduleBadge`，鼠标停一下显示完整的一句和 ⌘ 数字）；然后是清单、过滤器、标签、已完成 / 垃圾桶；最底下是账号行。选中的是 `SidebarItem`（一个视图，或者一个模块）：`model.sidebarSelection` / `model.choose(_:)`。点视图就是任务模块，点模块行就是那个模块；“显示”菜单里每个模块一项 ⌘1–⌘6（⌘1 回到上次的视图）。唯一会出现和消失的是账号行上面的小月历：日历在屏幕上、窗口又够高（侧栏 620 点以上）时才有。
  - 整个窗口是**一个** `NavigationSplitView`（侧栏 + 右边），换模块只换右边，所以侧栏的宽度、滚动位置、选中都留着。不要再给哪个模块单独套一层分栏。
  - 任务模块在右边自己分两半（`MacTasksSplit`）：`TaskListArea`，右边是详情（多选时是批量面板）。列表布局时详情一直在；看板和时间线要宽度，有任务打开（或多选）时才出现，标题行里有关闭按钮。中间的分隔线能拖（自己占 9 点宽，见第 10 节；详情 280–560，存在 `ot.taskDetailWidth`，双击回到 380，VoiceOver 里是一个可调的“详情宽度”），窗口窄时详情先让（`TaskSplitLogic.detailWidth`：列表至少 280，详情最少 220）。详情作为旁边的一栏时，“更多”菜单和关闭按钮在它自己的标题行里（环境值 `taskDetailChrome`，日历旁边的详情也是），窗口的工具栏只归列表：列表的按钮后面垫了一个和详情一样宽的空白项（`toolbarTrailingInset`），所以它们停在列表上方。
  - 日历在右边是 `CalendarPane`：日历，旁边是打开的任务或批量面板（放不下时改成 sheet / 底部操作栏）。要显示哪些清单、显示已完成 / 农历这些开关在工具栏的“更多”里。
  - 效率的四个模块各自占满右边（自己的 `NavigationStack`）。
  - 窗口最小 760×460，默认 1180×760。
- **iOS / iPadOS**：`TabView`，宽屏每个模块一个标签（`Shell/ModuleScreen.swift`），iPhone 上四个效率模块合成一个“效率”标签（导航标题是切换菜单）；最后是“搜索”标签。每个标签自己占满：iPad 上任务是三栏 `NavigationSplitView`（`TasksSplitView`；看板和时间线时两栏加 `.inspector`），日历是两栏（`CalendarSidebar`：小月历、要显示的清单、显示开关），效率模块没有侧栏（标签已经是它们了）；iPhone 和窄窗口是导航栈。宽度由 `horizontalSizeClass` 决定（`AppModel.width`）。两种布局之间切换时打开的视图和任务保留。设置：iPhone 在任务首页右上角，iPad 在任务侧栏的工具栏。
- **衔接的规矩**：
  - 换视图、换模块时清空多选（`model.selection`）；换模块在宽屏上还关掉打开的任务（Flutter 版如此），手机上各标签的页面栈保留。日历打开的任务在 `model.calendar.openTaskId`，和任务模块的 `selectedTaskId` 分开。
  - 应用层面的对话框（确认、单行输入、清单编辑、从菜单打开的日期对话框、过滤器编辑器、设置、快速添加）都经 `model.present` 由 `DialogHost` 显示；组件内部指着自己控件的弹出框（日期对话框的 popover、批量面板的标签、看板分组的改名等）留在组件里。
  - 工具栏：每个模块只在自己的视图上加按钮，外壳不加通用按钮（Mac 的搜索在侧栏顶上）。
- **菜单栏命令**（`AppCommands`，经 `.focusedSceneValue(\.appModel, …)` 找到当前窗口，文件头有完整的表）：
  - 文件 › 新建任务 ⌘N、新建清单 ⇧⌘N；编辑 › 搜索 ⌘F（⌘A、Esc 归列表和日历自己）。
  - 显示 › 各模块 ⌘1–⌘6；任务模块的显示为列表 / 看板 / 时间线 ⌃⌘1–3、显示已完成 ⇧⌘H；日历的日 / 3天 / 周 / 月 / 日程 ⌃⌘1–5、年、多周；放大 ⌘+（⌘= 也行，`InterfaceSizeKeys`）、缩小 ⌘-、实际大小 ⌘0（界面大小，不要窗口在前台）。
  - 前往 › 今天 / 明天 / 最近7天 / 收集箱 ⇧⌘1–4、各清单、已完成、垃圾桶；日历的回到今天 ⌃⌘T、上一页 ⌃⌘←、下一页 ⌃⌘→。
  - 任务 › 完成 ⌘↩、日期（今天 ⌃⌘T、明天 ⌃⌘M、下周一、选择日期… ⌘D、清除日期）、优先级 ⌥⌘1/2/3/0、置顶 ⇧⌘P、跳过此次、创建副本、删除 ⌘⌫。对打开的任务（在日历里是日历打开的），有多选时完成、优先级、删除对所选的。
  - 清单 › 编辑清单、添加分组、删除清单（当前清单）。
  - 两个模块共用的快捷键（⌃⌘1–3、⌃⌘T）同一时间只有一个可用；日历的单键（D W M A T ← →）只在日历有焦点时生效，不进菜单，所以不会抢输入框里的字。撤销提示同时登记到窗口的 `UndoManager`，⌘Z 也能撤销。新命令加在 `AppCommands` 对应的菜单里，先查这张表别撞键。
- **窗口恢复**（`Shell/WindowRestoration.swift`）：每个窗口用 `@SceneStorage` 记住模块、视图和打开的任务，数据到了以后恢复；有 `-OTOpen` 时不恢复。日历的模式和效率模块的状态在各自的本机设置里，不靠这个。

任务模块（规格是 Flutter 版的 sidebar / task_list_pane / task_tile / task_detail / quick_add_field / task_actions / section_actions）：

- **侧栏**（`Tasks/ViewsList.swift`，Mac 上也是整个窗口的侧栏，见上）：智能清单、（Mac：其他模块各一行）、清单（标题旁的 + 添加；右键 / 长按编辑、删除（先确认）；拖动排序）、过滤器（+ 和“编辑”打开过滤器编辑器）、标签、已完成 / 垃圾桶，每项带未完成数。
- **列表**（`TaskListArea` → `LayoutContent` → `TaskListView`）：按视图的 `ViewPrefs`（分组、排序、布局）显示，“显示选项”（⋯）里改，存在 `key_values`；“显示已完成”只在这个窗口有效（Flutter 版没有这一项，没存进 `ViewPrefs`）。分组可折叠；清单的自定义分组标题带 ⋯（重命名、上移、下移、删除分组）；今天 / 最近7天里空的日子也显示（不带数字、灰色）。垃圾桶有“清空”（先确认）和底部说明。拖动（`Drag/TaskListDrag.swift`）：Mac 上行能拖到别的位置、别的分组（改日期 / 清单 / 优先级），多选的一起走；iOS 和 iPadOS 上要先进“排序”：在手动排序的分组里长按任务行的右端（最后 64 点），列表进编辑模式，这些行右边出现系统的 ≡ 把手，拖把手在本分组里调顺序，右上角“完成”退出（离开这个视图也会退出）；长按行的其他地方还是菜单（第 10 节）。
- **快速添加**（`QuickAddField`）：边输入边高亮识别出的日期、时间、重复、#标签、!优先级，末尾显示识别出的日期；回车添加，带上当前视图的默认值（`quickAddDefaults`），有日期时加上设置里的默认提醒；新任务不在当前视图里时提示加到了哪。Mac 和 iPad 在列表顶上（⌘N 让它获得焦点），iPhone 是导航栏“+”弹出的 sheet。
- **详情**：标题、标签（点掉 / 添加）、描述（停 0.4 秒或离开时保存）；日期一行（点开日期对话框，重复和提醒的文字列在下面）；清单、优先级、置顶；子任务（勾选、改名、删除、拖动排序、添加）；垃圾桶里的任务只读，可以恢复 / 永久删除。
- **右键菜单 / 长按菜单**（`TaskMenu`，也是详情的“更多”）：完成；今天 / 明天 / 下周一 / 选择日期… / 清除日期 / 跳过此次；优先级；移到清单；标签；置顶；创建副本；删除。iOS 滑动：左滑出“完成”，右滑出“删除 / 置顶 / 明天”。完成重复任务、删除、跳过此次之后底部有提示，前两种带“撤销”。
- **多选**（`Tasks/TaskListPicking.swift`、`Model/AppModel+Batch.swift`）：列表用系统 List 自带的集合选择，⌘ 点选（第一次带上正开着的任务）、Shift 连选（按显示顺序，折叠的分组不在里面）、⌘A（光标在输入框里时归输入框），结果放进 `model.selection`；不带修饰键点一个就是打开它，Esc 取消。iPhone 在长按菜单里点“多选”进入列表的编辑模式，之后点一下选一个，右上角“完成”退出。垃圾桶里不能多选。打开的任务是 `model.selectedTaskId`，和多选分开：有多选时行的高亮看多选。看板、时间线、日历也用 `model.selection.tap(_:modifiers:order:current:)`，顺序用自己屏幕上的顺序（列表的是 `model.shownOrder(in:)`）。
- **批量操作**：有多选时宽屏右边的详情换成 `BatchPanel`（`BatchDetail`），iPhone 底部是 `batchBottomBar`（这时不显示加号）。每个 `BatchAction` 在 `model.performBatch(_:)` 里一个一个调 TaskRepo；完成和删除之后清空选择，底部提示可以撤销（重复任务的完成用 `undoRepeatCompletion` 撤回）。

### AppModel：状态放哪

`AppModel`（`@Observable`，一个窗口一个；`RootView` 用 `.environment` 传下去，视图里 `@Environment(AppModel.self)` 取）只放共用的东西：服务（`database`、`repo`、`settings`）、位置（`module`、`view`、`selectedTaskId`、`width`、`phonePath`）、数据（`data`、`now`）。每个功能自己的状态是一个 `@Observable` 子模型，一个文件，挂在 `AppModel` 上一个 `let`：

| 子模型 | 管什么 |
|---|---|
| `model.selection`（`SelectionModel`） | 多选：包领域层的 `TaskSelection`，`tap(_:modifiers:order:current:)`、`replace(with:)`、`selectAll`、`clear`、iOS 的 `isPicking`；换视图、换模块时清空 |
| `model.notices`（`Notices`） | 底部提示和撤销（`show(_:undo:)`） |
| `model.present`（`Presentation`） | 要显示的对话框：确认、单行输入、清单编辑、日期对话框、过滤器编辑、设置、快速添加 |
| `model.search`（`SearchState`） | 搜索是否打开（macOS 浮层 / iOS 搜索标签页）、最近搜索；打开结果用 `model.openSearchResult(_:)` |
| `model.taskList`（`TaskListState`） | 分组折叠、显示已完成、快速添加的焦点 |
| `model.calendar`（`CalendarModel`） | 日历的模式、锚点、打开的任务、手机上的页面栈（`Calendar/CalendarWiring.swift` 接到数据） |
| `model.efficiency`（`EfficiencyModel`） | 效率模块：上次用的模块、要打开的习惯 / 倒数日（`Efficiency/App/`） |

新功能照这个样子加自己的子模型，不往 `AppModel` 里塞字段，几个人同时加也不会改到同一处。

### 读数据

- `AppModel.start()` 先跑准备工作（种子数据），再用 `database.observeTaskData()`（`OpenTodoData/TaskData.swift`：一个 GRDB 观察一次读五张表）订阅，最新快照在 `model.data`（`lists`、`tasks`（含垃圾桶）、`checklistItems`、`sections`、`filters`）。
- 界面用派生值：`lists` / `listsById`、`filters` / `filtersById` / `filterRules`、`sectionsByList`、`tags`、`task(_:)`、`selectedTask`、`checklist(of:)`、`checklistProgress(of:)`、`count(of:)`、`sections(for:)`（按 `ViewPrefs` 分组排序，领域层的 `buildSections`）、`prefs(for:)`、`title(of:)`、`showsList(in:)`、`today` / `now` / `timeZone`。都是快照的纯函数，数据一变界面自己重算。
- 设置和每个视图的偏好在 `model.settings`（`LocalSettings`，数据层的）：`settings.settings.defaults`、`settings.viewPrefs(for:)`，改用 `setGrouping` / `setSort` / `setLayout` / `setDefaults`。
- 需要别的数据（比如日历的范围查询）：在 `OpenTodoData` 加观察，在自己的子模型里订阅，不要往 `TaskData` 里加。

### 写数据（TaskRepo）

- 直接调 `model.repo` 的方法，包在 `model.run { try await model.repo.setPriority(id, .high) }` 里（失败会在底部提示，不会悄悄丢掉）。写完不用刷新，改动经观察回来。
- 写完还要显示点什么的，用 `AppModel+Actions.swift` 里现成的：`setDone`（重复任务带撤销）、`trash`（带撤销）、`restore`、`purge`、`askEmptyTrash`、`skip`、`setQuickDate`、`setSchedule(_:_:)`（日期对话框的结果）、`toggleTag` / `askNewTag`、`duplicate`、`quickAdd(_:target:)`、`addList` / `askDeleteList` / `moveList`、`editFilter` / `askDeleteFilter`、`askAddSection` / `askRenameSection` / `askDeleteSection` / `moveSection`、`moveChecklistItem`。新的带提示的操作也加在这里，名字照 Dart 版的处理函数。
- 要问一句再做的：`model.present.confirm = ConfirmRequest(title:message:action:destructive:) { … }`；要输入一行字：`model.present.textPrompt = TextPromptRequest(…) { text in … }`；底部提示：`model.notices.show("…", undo: { … })`。

### 打开某个任务（revealTask）

`model.revealTask(id)`：切到任务模块，任务在当前视图里就留在这里，否则去它所属的地方（`viewForTask`：今天 / 已完成 / 垃圾桶 / 它的清单），然后打开它（宽屏在详情栏，手机上推一页）。搜索、日历、提醒通知、看板都用它。数据还没来时会等第一份快照。

### 弹日期对话框

- 有按钮可以指着的（详情的日期行、工具栏按钮）：在按钮上加 `.scheduleEditor(isPresented:schedule:defaults:onCommit:)`（`Schedule/SchedulePresentation.swift`），`schedule` 用 `ScheduleDraft(task:)`，`onCommit` 里 `model.run { await model.setSchedule(task.id, draft) }`。
- 没有按钮的（右键菜单、菜单栏的“选择日期…”）：`model.present.schedule = ScheduleRequest(taskId:)`，`DialogHost` 用 sheet 显示，确定后自动写回。批量改日期用批量面板自己的选日子框（`Batch/`），每个任务保留各自的时间。

### 在列表区域换布局（看板、时间线）

`Tasks/TaskListArea.swift` 的 `LayoutContent` 按 `ListLayout` 分三支：列表 `TaskListView`、看板 `ListBoard`、时间线 `TaskTimeline`，新布局在这里加一行。哪些视图提供哪些布局看 `layouts(for:)`（清单：列表 / 看板 / 时间线；其他视图：列表 / 时间线；已完成和垃圾桶只有列表），“显示选项”里的布局选择、分组和排序会跟着变（看板不给分组，时间线用 `timelineGroupingsFor`）。你的视图从 `model.sections(for:)` 或 `model.data` 取任务，写操作同上；要带默认值加任务用 `QuickAddField(target: QuickAddTarget(listId:sectionId:…))`。

### 加一个模块

1. `Model/AppModule.swift` 加一个 case，写上 `title`、`symbol`、`tint`（Mac 侧栏里图标的颜色）。顺序就是侧栏、标签和 ⌘ 数字的顺序（现在六个，⌘1–⌘6，再加就到 ⌘7）。
2. 写这个模块的界面：一个占满所给空间的视图，自己带 `NavigationStack`（标题、工具栏按钮都在里面），窄屏（`model.width == .compact`）也是它。状态放自己的子模型。不要自己套 `NavigationSplitView`，也不要自己的侧栏：Mac 上侧栏是整个窗口的。
3. `Shell/MacShell.swift` 的 `detail` 里和 `Shell/ModuleScreen.swift`（iOS 的标签）的 `switch` 里各加一行返回它。Mac 的侧栏、“显示”菜单、iOS 的标签都会自动出现。想在侧栏那一行的行尾说点什么，在 `moduleBadge` 里加。

### 加一个对话框

`Model/Presentation.swift` 加一个请求类型和属性，`Shell/DialogHost.swift` 加一个 `.sheet(item:)`。过滤器编辑器是 `FilterEditorSheet`（`Filters/FilterActions.swift`）。别的功能要编辑一条过滤规则（四象限、日历按过滤器筛），用 `FilterRuleRow` / `FilterRuleEditor`，用法见 `Filters/FilterRuleEditor.swift` 文件头。

### 加一个路由（-OTOpen）

1. `App/DebugLaunch.swift`：`DebugRoute` 加 case，`init?(_:)` 解析、`text` 写回（`DebugLaunchTests` 的往返用例加一条）。
2. `AppModel.apply(_:)` 里处理它（设好 `module` / `view` / 选中 / 某个 `present` 请求）；只属于一个功能的（比如 `schedule:`）由那个功能自己的调试展示器处理。路由在第一份快照到了以后才执行。
3. `AppModelTests` 加一个用例，再用 `scripts/shot.sh` 截一张看看。

### 启动和演示数据

- **AppServices**（数据层的启动器）：应用外壳（`App/OpenTodoApp.swift`）启动时用 `AppModel.launchServices(debug)`（`Model/AppLaunch.swift`）建一次，所有窗口和设置窗口共用。正式运行是真数据库（`AppServices.launch()`：系统通知、钥匙串）；调试启动带 `-OTDatabasePath` 时打开那个文件，通知放内存、令牌放库里，截图和界面测试不会弹系统对话框。打不开数据库时用内存库，窗口里提示一句。
- 每个窗口的 `AppModel.forLaunch(debug, services:)` 从它取 `repo` / `settings`，`model.services` 里还有 `sync`、`reminders`、`efficiency`。`start()` 时先跑 `services.start()`（提醒、新装时的欢迎清单、同步；重复调用无害）；`-OTSeed demo` 时不放欢迎清单，改填演示数据。
- `RootView` 把回前台 / 进后台告诉 services（`appDidBecomeActive` / `appDidEnterBackground`），从通知打开的东西交给 `model.handle(_:)`（任务用 `revealTask`，习惯和倒数日打开效率模块的那一项）。
- 设置：macOS 的设置窗口和 iOS 的设置 sheet 都是 `Settings/` 的 `OpenTodoSettingsView`（通用、任务、通知、专注、快速添加、账号、关于；`Shell/SettingsView.swift` 包了一层）；Mac 侧栏底部是账号行（`AccountSidebarItem`），点它打开设置。
- 演示数据（`Model/DemoData.swift`）经 `TaskRepo` 写进打开的那个库（库里已有任务就不写），和真实数据走同一条路；`DemoData.make(today:now:)` 给只要画东西的调试页一份同样的纯内存数据。五个清单（`work` 工作（分组“进行中 / 待安排”）、`life`、`shopping`、`reading`、`fitness`），二十几个任务，日期相对“今天”，各种情况都有，一个过滤器 `important-week`。ID 固定：`-OTOpen list:work`、`-OTOpen task:report`。

### 共用组件（`Components/`）

组件只吃模型（`TodoTask`、`TaskList`……）和简单值，不碰 `AppModel` 和数据源，哪个界面都能用。

| 组件 | 用途 |
|---|---|
| `TaskRow` | 任务行：优先级勾选框、标题（最多两行）、下面一行小字（日期、所在清单、子任务进度、标签）、置顶的图钉；完成的变灰，过期的日期标红。`TaskRow(task, now:, list:, showList:, checklist:) { 勾选 }`；选中、滑动、右键菜单由外面的列表加 |
| `PriorityCheckbox` | 圆形勾选框：圈是优先级颜色（无优先级是灰的，其他带一点底色），完成后是灰色实心带勾。点击区域 iOS 至少 28pt、Mac 20pt |
| `DueLabel` | 日期小标签：`dueLabel` 的文字（今天的只显示时间），后面跟重复、提醒的小图标；过期红色，其余灰色。`DueLabel(task, now:)` |
| `TagLabel` / `TagChips` | 标签：行里写成 `#工作`（强调色文字），详情里是胶囊 |
| `GroupHeader` | 分组标题：标题、个数（nil 不显示）、可选的折叠箭头；`alert` 时标题红色（已过期），`dimmed` 时灰色（空的日子） |
| `EmptyState` | 空状态：`EmptyState.forView(view)` 按视图给图标和文案（照 Flutter 版），`.noTaskSelected` 是详情栏的一行灰字 |
| `ViewIcon` | 智能清单 / 清单 / 过滤器 / 标签的图标：清单有 emoji 用 emoji，否则 SF Symbol。`.plain` 用在侧栏（颜色由行的 `.listItemTint(icon.tint)` 给，选中时系统会反白），`.badge` 用在 iOS 列表（彩色圆底白图标） |
| `Palette` | 强调色、优先级颜色（照 `app/lib/ui/theme.dart`）、过期红、清单颜色（ARGB 整数转 `Color`）；`SmartKind` 的 `title` / `symbol` / `tint` 也在这里 |

字号和间距只在 `TaskRow.Metrics` 里分平台定一次（标题 `.body`、小字 `.subheadline`，都是标准档的，经 `uiFont` / `uiScale` 跟着界面大小变），其余都用系统默认：列表样式（Mac `.inset`、iPhone `.plain`、侧栏 `.sidebar`、详情 `Form` 的 `.grouped`）、工具栏、标签栏的 Liquid Glass 都是系统自己画的，不要自己仿。

### 应用图标

`apple/scripts/make_icon.swift` 画出来（`swift apple/scripts/make_icon.swift`，加 `--preview <目录>` 另存一份 1024 的看）：青绿渐变底（#14A38B 上下各浅一点深一点），白色的三行清单，第一行的圆圈打了勾。iOS 是三张 1024 满版（浅色、深色、着色），macOS 是画好圆角方块和阴影的 16–1024 各尺寸，都写进 `App/Assets.xcassets/AppIcon.appiconset`。改图标就改脚本再跑一遍，不要手改 PNG。

## 8. 效率模块

习惯打卡、番茄专注、倒数纪念日、四象限是 Swift 版新加的（路线图 M5），Flutter 版没有。领域层在 `OpenTodoDomain/Efficiency/`（`Habits.swift`、`Focus.swift`、`Countdowns.swift`、`Matrix.swift`，名字算 ID 用的 `UUIDv5.swift`），测试是同名的 `*Tests.swift`。数据层：schema 8 的四张表（`habits`、`habit_checkins`、`focus_sessions`、`countdowns`），写操作走 `EfficiencyRepo`，同步记录类型 `habit`、`checkin`、`focus`、`countdown`（服务端白名单要先部署）；习惯和倒数日的提醒和任务的一起排（`EfficiencyReminders.swift`）。界面见本节末尾。

**共同约定**：记录和 `Models.swift` 一样是纯结构体，带 `createdAt` / `updatedAt` / `deletedAt` / `serverVersion` / `dirty`，字段只用简单的 JSON 类型（字符串、数字、布尔、数字数组；日期是 `Day`，存 `YYYY-MM-DD`；时刻是毫秒）；枚举存数字，读到不认识的数字回落到默认值。“今天”“现在”由调用方传入。用户新建的记录（习惯、倒数日）ID 照旧用 UUID v7；**由内容决定的记录 ID 用 UUID v5**（`uuidV5(namespace:name:)`，和 Dart `uuid` 包的 `v5` 结果一样），两台设备离线时各自记下的“同一件事”同步后只剩一条（后写的覆盖先写的）。只存本机的设置是 `key_values` 里的 JSON，读不出来或缺字段时用默认值。

### 习惯

- `Habit`：`name`、`emoji`、`color`（ARGB）、`goalKind`（0 打卡一次即完成 / 1 计数）、`goal`（计数时每天的目标量）、`step`（点一下加多少）、`unit`、`frequency`、`reminders`（当天的分钟数）、`startDate`、`section`（0 任意 / 1 上午 / 2 下午 / 3 晚上，页面上按上午、下午、晚上、任意排）、`archivedAt`、`sortOrder`。
- `frequency` 存成 RRULE 风格的文字：`FREQ=DAILY`、`FREQ=WEEKLY;BYDAY=MO,WE,FR`（每周指定几天）、`FREQ=WEEKLY;TIMES=3`（每周任意 3 天）。读不懂的当每天。
- `HabitCheckin`：`habitId`、`day`、`value`（当天记下的量）、`status`（0 记了但没完成 / 1 完成 / 2 放弃这天）。**ID = UUID v5(`habitCheckinNamespace`, `<habitId>/<YYYY-MM-DD>`)**，一个习惯一天一条。取消打卡写删除标记，再打卡时同一 ID 覆盖回来。计数的打卡在写入时按目标算出 `status`，之后改目标不回头改旧记录；“完成”只看 `status`。
- 该不该打卡：开始日期以前都不算；每周指定几天的只在那几天；每周 N 次的每天都可以打。
- **连续天数**：按天的习惯（每天、每周指定几天），连续是一串完成的日子，中间没有“该打卡却没完成”的日子：不该打卡的日子不打断（那天打了卡也算一天），今天还没打不打断，放弃和只完成一部分算没完成。当前连续是到今天（今天还没打就到昨天）为止的那一串。每周 N 次的习惯按周算（周一起），一周完成 N 天算保持，单位是周；开始那一周只要求剩下的天数；本周没过完不打断。
- 月完成率：从开始日期（或月初）到今天，完成的应打卡日 ÷ 应打卡日；每周 N 次的每周最多要求 N 天（月初月末的半周按天数封顶）。不该打卡的日子打了卡不计入。
- 今天的打卡列表：没删、没归档、已开始、今天该打卡的习惯，按分区分组、组内按 `sortOrder`；每周 N 次的本周已经够了就不再出现（今天打过的除外）。

### 专注

- `FocusSession`：`startedAt` / `endedAt`（毫秒）、`duration`（秒，有效专注时长，不含暂停）、`kind`（0 番茄 / 1 正计时）、`completed`、`taskId` / `habitId`（可空）、`note`。**ID = UUID v5(`focusSessionNamespace`, 开始的毫秒数)**：同一次计时不管保存几次都是一条。
- **怎么算有效**：有效时长不足 5 分钟（`focusMinimumSeconds`）的放弃或提前完成不记录；番茄走满设定时长的总是记录（哪怕设成了 2 分钟）。放弃的番茄（满 5 分钟）记一条 `completed = false`，算专注时长、不算番茄数；“番茄数”只数 `kind = 0` 且 `completed` 的。正计时结束就是完成。
- 计时器 `FocusTimer` 是纯值（`Codable`，存本机），时间由调用方传入；只存“这段从什么时候开始跑”和“之前累计了多少毫秒”，不存“还剩几秒”，应用被杀掉后读回来调 `tick(at:)` 就能补上：走完的番茄按它走完的那一刻记录，打开了自动开始的话下一段从那一刻接着开始。每 `longBreakEvery` 个番茄后是长休息，休息不能暂停。
- `FocusSettings`：番茄 25、短休息 5、长休息 15（分钟），每 4 个一次长休息，自动开始下一个默认关；存 `key_values` 的 `focus.settings`。
- 统计按开始时刻所在的那一天算（跨午夜的算前一天），时区由调用方传入。按天 / 周（周一起）/ 月的柱状图序列包括空的那几格；按任务 / 清单的分布从大到小，没有任务的归到 nil；某天的时间轴把跨午夜的截到当天。

### 倒数纪念日

- `Countdown`：`title`、`kind`（0 倒数日 / 1 纪念日 / 2 生日 / 3 节日）、`date`（事件本身的公历日期，农历的也存公历）、`lunar`、`repeats`（0 不重复 / 1 每年 / 2 每月）、`emoji`、`color`、`showInToday`、`reminders`、`pinnedAt`、`sortOrder`。`reminders` 和全天任务的提醒一样是相对那天 0 点的分钟数（提前 1 天 9:00 是 `-900`）。
- 下一次：还没到就是 `date` 本身；重复的取今天或以后的第一次。公历每年 / 每月遇到没有那一天的月份取月底（2月29日在平年是 28 日）。农历照重复任务的规矩：每年的取普通月（闰月出生的在那个月份的普通月过），没有三十的取二十九；每月的闰月也算一个月。
- 显示：纪念日到了以后从 `date` 往上数（已经 N 天）；其余数到下一次（还有 N 天），不重复的过了就数过了几天。格式有天数、年月天（按日对日数整月，月底照 `addingMonths` 封顶）、周天，零的部分不写，当天是“今天”。
- 岁数是周岁；农历生日过了农历生日才长一岁。
- 列表：置顶在前；每部分里还没到的按剩余天数从少到多，过了的按过去天数从少到多。“今天”里显示勾了 `showInToday`、下一次就是今天的。

### 四象限

- `MatrixPrefs` 存 `key_values` 的 `matrix.prefs`：四个象限，每个是名字加过滤规则（规则是和 `TaskFilter.rule` 一样的 JSON 文字）。默认按优先级：高 / 中 / 低 / 无。缺的象限用默认值补齐，多的丢掉。
- 分象限：未完成、没进垃圾桶、没删除的任务，放进第一个符合的象限，都不符合的不显示；象限内排序和列表按时间排一样（置顶在前，然后日期、时间、优先级）。
- 拖进某个象限：用过滤器快速添加的那套提示（规则是“且”、某个字段只指定了一个值时才用）改清单（换清单时清掉分组）、日期（保留时间和时间段）、标签（加上）、优先级。改完不一定满足象限的全部条件。

### 界面组件

`OpenTodoUI/Efficiency/` 里每个模块一个根视图，都是自包含的：输入是值，改动以“整条要写的记录”经回调交出去（删除、取消打卡就是带 `deletedAt` 的记录），自己不碰数据库。导航怎么挂由调用方决定。

- `HabitsRootView(habits:checkins:today:onSaveHabit:onSaveCheckin:newId:)`：周条（最近 7 天，点一天可补打卡）、按时段分组的打卡列表（打卡一次的点一下切换，计数的点一下加一步，右键 / 长按输入数量、放弃这天、取消打卡）、详情（统计、月历、热力图、归档、删除）、全部习惯、编辑器。
- `FocusRootView(timer:settings:sessions:tasks:lists:timeZone:onTimerChange:onSaveSession:onSettingsChange:onPickTask:onEndScheduled:)`：计时器状态每次变化都经 `onTimerChange` 交出去保存，下次启动传回来就接着算；`onEndScheduled` 给出这一段结束的时刻（nil 表示没有在跑），调用方用它排通知；`onPickTask` 为 nil 时用内置的简单任务列表。
- `CountdownsRootView(countdowns:today:onSave:formats:onFormatChange:newId:)`：卡片的显示格式点数字切换，想记住就接 `onFormatChange`。
- `MatrixRootView(tasks:prefs:now:lists:onToggleDone:onOpenTask:onMoveTask:onQuickAdd:onPrefsChange:ruleEditor:)`：`onMoveTask(旧, 新)` 给出拖进别的象限后该保存的任务；`onQuickAdd(标题, QuickAddDefaults)`；`ruleEditor` 是规则编辑器的插槽，不给时用只选优先级的简单版。

调试路由 `-OTOpen habits|focus|countdowns|matrix[:状态]` 用内存里的演示数据打开，状态见 `EfficiencyDebug.swift` 文件头。

### 接入应用

- 四个模块是 `AppModule` 的 `matrix`、`focus`、`habits`、`countdowns`（⌘3–⌘6），`MacShell` 和 `ModuleScreen` 都交给 `EfficiencyScreen`（`Efficiency/App/`），它只管把模块自己的界面接到数据上，不带侧栏：Mac 上四个模块是窗口侧栏里的四行（行尾的近况是 `moduleBadge`，鼠标停一下的那句是 `efficiencySummary`：今天的打卡、今天的专注、最近的倒数日、紧急的任务数），iPad 上是四个标签。iPhone 上四个模块合成一个“效率”标签（任务 / 日历 / 效率 / 搜索），显示上次用的那个，导航栏标题是切换模块的菜单（`toolbarTitleMenu`）。
- 状态在 `model.efficiency`（`EfficiencyModel`）：四个观察（第一次需要时启动，`RootView` 上的 `EfficiencyDebugPresenter` 在窗口出现时启动）、写操作（界面交出来的整条记录转成 `EfficiencyRepo` 调用；删除倒数日和专注记录带撤销）、专注计时器（每次变化存 `LocalSettings.setFocusTimer`，启动时读回并补算；别的模块在前台时每 5 秒看一次钟，走完的番茄照样记录）。
- 专注结束的通知由 `FocusEndNotifier` 用固定 ID `opentodo.focus.end` 排（提醒调度只管数字 ID，不会动它），每次计时器变化重排或取消。
- 任务的右键菜单 / 详情的“更多”里有“开始专注”（`StartFocusButton`）：空闲时开始一个番茄并关联这个任务，已经在专注就改关联，然后切到专注模块。
- “今天”智能清单顶上一行显示勾了“显示在今天”、今天正好是那天的倒数日（`TodayCountdownsRow`，在 `TaskListView` 里挂一行），点了打开倒数日详情。
- 四象限：任务来自 `model.data`，勾选走 `model.setDone`，点开走 `revealTask`，拖到别的象限写 `TaskRepo.updateTask`，块里的快速添加走 `model.quickAdd`（会识别日期等），象限的名字和规则用过滤器编辑器（`FilterEditor`）改，`MatrixPrefs` 存本机。
- `-OTSeed demo` 时 `EfficiencyDemo.seed` 经 `EfficiencyRepo` 写演示数据（六个习惯和几个月的打卡、最近十周的专注记录、七个倒数日），库里已有习惯就不写。

## 9. 系统集成

小组件、分享扩展、快捷指令 / Siri、Spotlight、macOS 菜单栏小窗和全局快捷键。和扩展共用的逻辑在 `OpenTodoSystem`（有测试），应用这边的在 `OpenTodoUI/System/`。

### 目标和 entitlement

| 目标 | 包名（调试版 / 正式版） | 内容 |
|---|---|---|
| `OpenTodo` | `com.liaoxingyi.opentodo.dev` / `com.liaoxingyi.opentodo` | 应用；`Intents/` 和 `App/AppShortcuts.swift` |
| `OpenTodoWidgets` | `….widgets` | 小组件：今天（小 / 中 / 大）、快速添加、倒数日（可选哪个）、习惯；`Intents/` |
| `OpenTodoShare` | `….share` | 分享扩展：文字 / 链接存成任务 |

- 三个目标都有 App Group entitlement，组名是构建设置 `OT_APP_GROUP`（`project.yml` 顶上）：iOS 是 `group.com.liaoxingyi.opentodo`，调试版加 `.dev`；macOS 带团队前缀 `$(TeamIdentifierPrefix)group.com.liaoxingyi.opentodo(.dev)`。组名也写进各自 Info.plist 的 `OTAppGroup`，数据层的 `AppDatabase.defaultURL()` 读它。
- 链接的 scheme 是构建设置 `OT_URL_SCHEME`：正式版 `opentodo`，调试版 `opentodo-dev`（两个版本能同时装）。写在 Info.plist 的 `CFBundleURLTypes` 和 `OTURLScheme`。
- macOS 的应用和扩展都开沙盒（扩展必须）；应用另有 `network.client`。

### 数据怎么共享

- 数据库在 App Group 容器里（`Library/Application Support/opentodo.sqlite`）。第一次在容器里打开时，把老位置（Flutter 版或没有 App Group 时的 Swift 版）的库复制进去，老文件留着当备份（`AppDatabase.moveIntoGroup`）。
- 小组件只读打开（`WidgetStore`，没有库时当作空的）。小组件上的勾选、分享扩展、快捷指令用 `SharedWriter` 经 `TaskRepo` 写，行照常标记待同步，应用下次同步时发出去。
- 写完发一个 Darwin 通知（`ChangeSignal`，名字以组名开头，macOS 沙盒才放行）；应用收到、或回到前台时，进程级的 `SystemSync` 读一遍数据交给登记过的每个 `AppModel`（各窗口的、菜单栏小窗和快速添加面板共用的那个；GRDB 的观察看不到别的进程的提交）。窗口全关了也照样（macOS 上应用还开着菜单栏和快捷键）。iOS 退到后台时应用让 GRDB 放开文件（`AppServices.appDidEnterBackground`），否则会被系统杀掉（0xdead10cc）。
- 同一个进程里所有窗口、菜单栏小窗、快速添加面板共用应用的 `AppServices`（一个数据库连接池），一处改了处处看得到。
- 数据变了（应用里写的，或别的进程写的），1 秒后（防抖）`WidgetCenter.shared.reloadAllTimelines()`，同时重建 Spotlight 索引；这也在 `SystemSync` 里，盯的是数据库本身，不靠窗口（未完成的任务，标题、清单、日期、备注第一行，标签当关键词）。今天小组件的时间线按“今天的任务到点变红的时刻”和零点刷新（`widgetRefreshTimes`）。

### 链接

`opentodo://task/<id>`、`list/<id>`、`today`、`quickadd`、`habits`、`countdowns`、`focus`（`AppLink`）。小组件点任务、Spotlight 结果、“打开清单”快捷指令、菜单栏小窗点任务都走它，由根视图的 `SystemIntegration` 打开；习惯、倒数日、专注切到对应的效率模块（习惯小组件、倒数日小组件、菜单栏的“今日专注”）。

### App Intents

“添加任务”（标题、可选日期、可选时间、可选清单，不打开应用；只给时间就是今天，`intentDue`）、“打开清单”、“完成任务”（只给小组件按钮用）。应用自带 App Shortcuts 短语（“用 OpenTodo 添加任务”）。倒数日小组件的“选择倒数日”也是一个 intent。

### macOS：菜单栏和快捷键

- 菜单栏小窗（`MenuBarExtra`，窗口样式）：今天的任务（勾选完成、点一下在主窗口打开）、一行快速添加（加到今天）、今天的专注时长。
- 全局快捷键默认 ⌃⇧A，用 Carbon 的 `RegisterEventHotKey`（沙盒里能用，不要辅助功能权限）。按下后屏幕上方浮出一行快速添加（非激活的 `NSPanel`，像 Spotlight），就是任务模块的快速添加输入框，带解析高亮；回车添加到收集箱（写了日期就按日期）并消失，Esc 或点别处取消。快捷键被别的应用占用时设置里会提示。
- 设置 → 快速添加：菜单栏开关、快捷键开关和录制。存在本机 UserDefaults（`IntegrationPrefs`），不同步。
- 脚本启动的调试版（带 `-OTDatabasePath`）不注册全局快捷键，免得抢走用户的键。截图用 `-OTOpen system:menubar|quickpanel|settings` 把它们摆进主窗口。

### 真机签名（第一次给 iPhone 编时，账号主人自己做）

模拟器和 macOS 调试版不用开发者后台做任何事。给真机签名时，iOS 的 App Group 要在开发者账号里有：

1. `build.sh` 默认**不**带 `-allowProvisioningUpdates`，不会改账号。要让 Xcode 自动注册时显式打开：`OT_ALLOW_PROVISIONING=1 ./scripts/build.sh …`（或在 Xcode 里打开工程，Signing & Capabilities 里勾上 App Groups，点 Fix）。
2. 它会做的事：在 developer.apple.com 注册 App Group `group.com.liaoxingyi.opentodo`（调试版 `.dev`），给 `com.liaoxingyi.opentodo(.dev)`、`….widgets`、`….share` 三个 App ID 开 App Groups 能力并选上这个组，重新生成开发用的描述文件。手动在网页上做也一样。
3. 之后正常编、装。macOS 用团队前缀的组名，不需要注册。

### Release 配置

- 只看能不能编：`OT_CONFIGURATION=Release ./scripts/build.sh macos`（或 `ios`，模拟器），产物在 `.derived/Build/Products/Release/`、`Release-iphonesimulator/`。**不要运行**：Release 是正式包名 `com.liaoxingyi.opentodo`，一跑就打开用户真实的数据库和 App Group 容器。
- 现在两个平台都编得过，不需要开发者后台做任何事：macOS 用开发证书签名（发布的用 Developer ID，见下面“发布”），组是带团队前缀的 `<团队>.group.com.liaoxingyi.opentodo`，不需要描述文件；iOS 模拟器不签真实描述文件。应用、`….widgets`、`….share` 三个包名和 `opentodo` 这个 scheme 都按正式版的出来。
- 还没做、需要账号主人做的：给 iPhone 编 Release（和调试版一样，先在开发者账号里注册 `group.com.liaoxingyi.opentodo` 并给三个 App ID 打开，见上面“真机签名”），会动账号。macOS 版发给别人见下面“发布”。

### 发布（macOS）

只发 macOS 版：GitHub Release 上放 `OpenTodo-<版本>.dmg`、`.zip` 和 `SHA256SUMS`，Homebrew 装的是 `kadaliao/tap` 里的 `opentodo` cask（用 DMG）。iOS 版不在这里发。

1. 改动随手记进根目录 `CHANGELOG.md` 的“未发布”。发版时把它改成 `## [x.y.z] - 日期`，写给用户看的话：发布页的说明就是这一节。
2. 改 `project.yml` 的 `MARKETING_VERSION`（三个 Info.plist 都引用它，改完跑 `generate.sh`），提交并推送。
3. `cd apple && ./scripts/release.sh --publish`。它先检查：工作区干净、HEAD 就是 origin/main、标签 `v<版本>` 没被别的提交占、这个版本的 Release 还没有、更新记录里有这一节。然后编 Release、签名、公证并装订 App 和 DMG（要联网，几分钟），打出三个文件，打标签推上去，建 GitHub Release，最后触发 tap 的 `bump.yml`：它把 cask 的版本号和 sha256 改成新的（不触发也会在 6 小时内自己跑）。

- 签名用 Developer ID Application 证书，开 Hardened Runtime，不带 `get-task-allow`，不要描述文件（macOS 的 App Group 带团队前缀）。没有描述文件就没有 `application-identifier`，同步登录的令牌存在登录钥匙串里（`TokenStore`）。从开发证书签的版本换过来，第一次打开时系统可能问能不能读这一项，点“始终允许”。
- 公证用 App Store Connect 的 API key：`NOTARY_KEY`（.p8 文件）、`NOTARY_KEY_ID`、`NOTARY_ISSUER`，都没给时从 `~/.appstoreconnect/notary.env` 读（和 suck-my-disk 的发布脚本共用）；也可以用 notarytool 存在钥匙串里的配置（`NOTARY_PROFILE`，不在登录钥匙串里时再给 `NOTARY_KEYCHAIN`）。凭据在编译之前就先试一次。只想看看能不能签：`NOTARIZE=0 ./scripts/release.sh`，不公证、不能发布，产物在 `apple/build/release/`。
- Build number 是提交数（`git rev-list --count HEAD`），只会变大。
- 编出来的 App 不留在构建目录、也从 LaunchServices 注销：它是正式包名，一打开就用真实数据库。
- cask 的 `zap` 会删掉 App Group 容器，数据库就在里面（同步过的服务器上还有）。

### 测试和截图

- `OpenTodoSystemTests`：链接解析、今天小组件显示哪些任务和刷新时刻、习惯 / 倒数日 / 专注的内容、分享内容转任务、扩展写库、快捷键的显示和存储、Spotlight 的内容。
- 小组件的样子和分享扩展要在模拟器或真机上看（小组件预览截不了图）；macOS 的菜单栏小窗、快速添加面板、设置用上面的调试路由截图。

## 10. 踩过的坑

**截图**
- `-OTSnapshot` 的自绘（AppKit `cacheDisplay`）画不出 Liquid Glass 等材质，也画不出系统 `List`（底下是 `NSTableView`）和 `Form` 的内容：侧栏、任务列表、详情都是空白，只剩标题栏、工具栏和自己画的视图（日历、看板、时间线能画出来）。拿它只能确认路由打开了、数据到了（标题旁的“N 个任务”），不能拿来看列表的样子。
- 屏幕锁着或休眠时 `screencapture -l<窗口号>` 失败或截出黑图，权限检查照样说“有”。夜里自动跑截图时退回 `OT_MAC_METHOD=self`，或者先只看 iOS 模拟器的（`simctl io` 不受锁屏影响）。
- 演示数据经 `TaskRepo` 一条条写，机器忙的时候要几秒；路由要等第一份数据才执行，截早了是空的默认页。自绘截图现在等 `model.loaded` 再拍。
- 自绘截图里，放在 `NavigationStack` 里的竖向 `ScrollView` 也是空白，`.inspector` 的内容也画不出来（嵌在横向 `ScrollView` 里的看板列能画出来）。
- 锁屏时 `caffeinate -u` 叫不醒屏幕，报 “Failed to create UserIsActive assertion”。
- 截图看不了的布局，可以直接跑 `OpenTodo.app/Contents/MacOS/OpenTodo -OTOpen …`，在视图里临时用 `onGeometryChange` / `onScrollGeometryChange` 往 stderr 打坐标和滚动位置来核对，看完删掉。
- 同时开的模拟器多了（几个 agent 各开一个、外加别人的）机器负载上到几百，CoreSimulator 卡死，连 `simctl list` 都不返回。所以并行时最多一个人开模拟器。
- Mac 上的 popover 是单独的窗口，按窗口截图（`screencapture -l`）和 `-OTSnapshot` 都截不到它。要看 popover 里的内容，做一个调试路由把那块内容直接摆在窗口里（日历的 `calendar-demo:panels`）。
- 在单元测试里用 `ImageRenderer` 把视图画成 PNG 可以在 macOS 上看自己画的组件（环、卡片、格子），深浅色都行；但 `Button`、`TextField` 画成黄底禁止符号，`ScrollView` / `List` 的内容是空的，只适合看不带控件的部分。

**SwiftUI**
- `.environment(model)` 要放在修饰器链的最外层：读 `@Environment(AppModel.self)` 的修饰器（对话框、提示条、截图）写在它外面会在启动时崩（“No Observable object of type AppModel found”）。单元测试不渲染视图，查不出来，要真启动一次。
- `OpenTodoUI` 里的类型名会挡住同名的系统类型和别的模块的类型，不报重名：时间线的 `TimelineView` 挡住了 SwiftUI 的 `TimelineView`（用系统那个要写 `SwiftUI.TimelineView`，否则编译器报“表达式太复杂”或参数对不上）；界面里的类挡住领域层的 `TaskSelection`。起名前在整个包里搜一下。
- macOS 的 `TabView` 只有放在 `Settings` 场景里才画成设置窗口那种工具栏图标标签；放在普通窗口里画成另一种标签条。调试路由要看设置的样子，只摆当前那一页的内容（`prefs:` 路由就这么做），整窗的样子要在真的设置窗口里看。
- iOS 的 `Form` 里，`TextField` 只显示占位文字、不显示标题（macOS 两个都显示），占位文字要自己写明是什么字段。macOS 的分组 `Form` 把标题放在左边、输入框在右边且没有边框，空着时那一格看起来只有一行字，没人知道能输入（“添加标签”“添加清单”就这样）；一行只有一个输入框的对话框要 `.labelsHidden()` 再给 `prompt:`，输入框才占满一行、显示占位文字。`Picker` 的标签写成两行时，选中的值会被挤到第三行，说明文字放到分组的脚注里。
- 调试路由的展示修饰器如果整个换掉内容，要挂在设置外观（`-OTAppearance` 的 `preferredColorScheme`）的那些修饰器里面，否则深色截图出来还是浅色。
- `List(selection:)` 绑 `Set` 时 ⌘ 点选、Shift 连选、⌘A 都是系统做的，但只给出结果集合，分不出“⌘ 点掉一个只剩一个”和“普通点了一下”，所以前者在 Swift 版里会变成打开那一个（Flutter 版保持多选）。
- `Text("\(year)年")` 里插的整数按本地化格式加千分位，显示成“2,026年”。插数字的文字用 `Text(verbatim:)`，或先拼成 `String` 再交给 `Text`（`navigationTitle(String)` 没这个问题）。
- `ScrollPosition.scrollTo(y:)` 在 `onAppear` 里调用时视图还没排好，不生效（时间格一直停在 0 点）。改用 `ScrollViewReader`：每个小时放一个带 `.id` 的占位，`onAppear` 里 `DispatchQueue.main.async { proxy.scrollTo(hour, anchor: .top) }`。
- 给 `Button` 加 `.disabled(true)` 会把它的标签整个变灰。只是不想让它能点（比如日视图里唯一那一天的标题）时用 `.allowsHitTesting(false)`。
- 系统拖放（`.onDrag` / `.onDrop`）没有“拖动取消了”的回调。拖的是什么记在自己的模型里，`onDrag` 开始时写入，`performDrop` 和 `dropExited` 里清掉；落点坐标是放下那个视图自己的坐标。判断“原地放下”（Flutter 版的 8 像素）可以用 `DropDelegate` 第一次看到拖动时的位置当起点。

- 放在 `.popover` 里的内容，在 iPad 上读到的 `horizontalSizeClass` 是 `.compact`（popover 本身窄）。要按“是不是宽屏弹出的 popover”定尺寸，在弹出它的那一层读 size class，再传进去（日期对话框的 `ScheduleSheetStyle(popover:)`）。popover 的高度按内容的理想高度来，里面是 `Form` 这类会滚动的内容时会偏矮，要给一个 `minHeight`。
- 挂在 `.inspector` 里的视图，它的 `.navigationTitle` 会顶掉外面那个界面的标题，面板关着也一样（iPhone 上日历的月份标题因此变成了“安排任务”）；给面板包一层自己的 `NavigationStack` 也挡不住。手机上改用 `.sheet` 弹出（sheet 里再放 `NavigationStack` 和标题），宽屏才用 inspector。
- iOS 的 `.toolbarTitleMenu` 在大标题上不显示那个小箭头，没人知道标题能点；要靠标题切换内容的界面用小标题（`.navigationBarTitleDisplayMode(.inline)`）。
- 用 `onGeometryChange` 量出一个视图的尺寸、再用这个尺寸去定它自己内容的大小，会形成回路：横向 `ScrollView` 的高度取决于内容，内容高度又取自量到的高度。再加上 `.ignoresSafeArea` 往下延伸，就会越长越高，直到整屏，把顶部顶进导航栏下面（手机上的时间线）。量尺寸要量一个只占满给定空间的空视图（`Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)`），真正的内容放在它的 `.overlay` 里。
- 多选时 iOS 列表编辑模式的选中行是系统的灰色（RGB 209,209,214，`systemGray4`），不是我们自己画的底色，不用改。
- 窄列里“星期 + 日期 + 农历”挤一行会互相盖住；用 `ViewThatFits`：放得下一行就一行，放不下就星期在上、日期在下、不显示农历。
- macOS 26 上用 `safeAreaInset` 挂在列表上下的栏（侧栏顶上的搜索、底下的账号行）没有滚动边缘效果，列表滚到它下面时文字叠在一起；改用 `safeAreaBar`。
- macOS 的工具栏：`.secondaryAction` 放在整条工具栏的中间，不是主按钮旁边（要放一起就都用 `.primaryAction`，iOS 再用 `.secondaryAction` 收进 … 菜单，见 `ToolbarItemPlacement.moreActions`）；三栏里 detail 栏的 `.primaryAction` 排在这一栏的最左边，要靠右先放 `ToolbarSpacer(.flexible)`；`.inspector` 内容里的 `.toolbar` 在 inspector 关着时照样显示，要按开没开加 `if`。
- `NavigationSplitView` 各栏的最小宽度加起来比窗口的最小宽度（`RootView` 的 760）大时，窗口缩到最窄各栏互相压住：侧栏的行被截掉左边、详情被截掉右边。各栏的 `min` 要加得起来。栏里有定宽的内容也会撑开这一栏（侧栏顶上以前有一排六个定宽的模块图标，界面大小特大时比侧栏最小宽度还宽，最窄窗口里三栏又压住了）。
- **`.inspector` 不会让**（macOS 26，2026-11-27 量过）：它旁边的内容不能比它窄（内容的最小宽度就是 inspector 当前的宽度），窗口变窄时 inspector 和侧栏都停在原来的宽度不往 `min` 收，结果 760 宽的窗口里排了 990 宽，左右都被挤出窗口。挂在 `NavigationSplitView` 外面时它有自己的一段工具栏，挂在 detail 栏里面时列表的工具栏按钮全跑到它上面。Mac 的任务详情因此不用它，自己分栏（`MacTasksSplit`）。给两栏 `NavigationSplitView` 的 detail 栏加 `navigationSplitViewColumnWidth` 也不行：1180 宽的窗口里内容照样被排宽了几十点。
- 想让工具栏按钮停在某一栏上方而不是窗口最右：在它们后面加一个空白的 `ToolbarItem`（`Color.clear.frame(width:)`），再 `.sharedBackgroundVisibility(.hidden)` 去掉它的玻璃底。
- `Divider()` 单独放在 `.overlay` 里是横的；要竖线放进 `HStack`。
- 纯 SwiftUI 的视图盖在 `List` / `Form` 的边上时点不到：它们底下是 AppKit 的滚动视图，鼠标先归它们，`zIndex` 也没用（用 `contentView.hitTest` 量过：分隔线两边用负的 padding 伸出去的 4 点落在 `NSClipView` 和表格上，只有线本身那 1 点归 SwiftUI）。要能点、能拖的东西得有自己的地方：任务列表和详情之间的分隔线自己占 9 点宽。这种“鼠标到底落在谁身上”的问题，在进程里合成事件测（第 5 节）：一个小程序把同样结构的视图放进窗口，`NSApp.postEvent` 发按下、拖动、抬起，每发一个转一下事件循环；头一次点击只是让窗口进入状态，先随便点一下再测。
- 换了模块但视图还是同一个（`EfficiencyScreen(module:)` 从习惯换到专注）时 `onAppear` 不会再跑，要跟着参数变的用 `onChange(of:initial:)`。
- macOS 上 `NSLog` 的内容用 `log show --predicate 'process == "OpenTodo"'` 查不到（模拟器里查得到）。要量窗口里的尺寸：临时在视图上 `onGeometryChange`，把数写进 `NSTemporaryDirectory()` 下的文件（沙盒里就是容器的 `Data/tmp/`），用 `open -g -n -F … -OTHiddenWindows yes` 启动后读文件；不用截图，ssh 会话里也能跑，十秒一轮。侧栏的宽度系统会记住（`-ApplePersistenceIgnoreState` 也不清），量出来不一定是 `ideal`。
- 选中的列表行（前台窗口里是强调色底、白字）里写死颜色的文字（`.tint`、红色）不会跟着变白，读 `@Environment(\.backgroundProminence)`，`.increased` 时改用 `.secondary`。
- 很宽的横向 `ScrollView`（时间线前后各十年，几十万点宽）在 Mac 窗口的分栏排版还没定下来时会被排回最开头，`ScrollPosition(x:)` 的初值也不再生效，时间线就开在十年前。`TimelineView` 现在等画布有了宽度才建滚动视图，宽窄两种排法用同一个 `AnyLayout` 不重建它，滚动位置一下子跳回开头时再放回去。这类问题用脚本截图不一定碰得上（有时对有时错），要多跑几次、往 stderr 打滚动位置看。
- `.preferredColorScheme` 只管它所在的窗口，`Settings` 场景的窗口要单独加（调试的 `-OTAppearance`）。
- macOS 26 上 `.dynamicTypeSize(.xxxLarge)` 放在窗口根上，`.body` 这些文字样式和 `@ScaledMetric` 都纹丝不动（截图逐像素一样），界面大小因此是自己的 `uiScale`（第 4 节）。
- 往环境里写一个值，哪怕和原来的一样，也会改样子：`.controlSize(.regular)` 让 `Form` 里的开关从它自己挑的小号变成普通大小、工具栏按钮变小；`.font(nil)`（或 `transformEnvironment` 原样写回）让侧栏分组标题从系统的小号粗体变成正文大小。要“标准档什么都不变”，只能在标准档干脆不加这个修饰器（`InterfaceScaleRoot`、`uiDefaultFont` 都是这样），代价是在标准和别的档之间切换时下面的视图会重建。
- 根上设了默认字体以后，`Section` 的 header / footer 和侧栏分组标题会直接用它（和行一样大、不加粗）；`NavigationLink` 的标签反而不吃根上的字体，标题要自己 `.uiFont(.body)`。表单里菜单样式 `Picker` 的当前值是系统画的弹出按钮，字号既不跟字体走，`.controlSize(.large / .extraLarge)` 也不变（只有开关变大），所以界面大小变大时它还是 13pt。

**启动和数据**
- 窗口的 `AppModel` 在启动时先填种子数据、再开始观察数据库，它的第一份快照之前不算“已加载”，`-OTOpen` 路由就等在这里。但系统集成的 `SystemSync` 收到外部写入的信号时，会把读到的快照交给所有登记过的模型，包括还在填种子的窗口：窗口拿到一份空快照，就以为已经加载，路由（`task:<id>`）在空库上执行，找不到任务就丢掉了，手机上停在首页。现在 `SystemSync` 跳过已经开始但还没收到第一份快照的模型（`AppModel.awaitingFirstSnapshot`）。

**移植 Dart 代码**
- Dart 的 `RegExp` 照 JavaScript，`NSRegularExpression` 是 ICU，有两处不一样：ICU 的 `\d` 也认全角数字，`\b` 把汉字当单词字符（`3pm健身` 里 `pm` 后面就不算单词边界）。照搬 Dart 的正则时 `\d` 写成 `[0-9]`，`\b` 写成 `(?![A-Za-z0-9_])` 这样的明确写法。
- Dart 字符串的位置是 UTF-16 下标，`NSRegularExpression` 的 `NSRange` 也是，正好对得上；Swift `String` 的 `Character` 计数对不上（表情、组合字符）。需要和 Dart 一样的位置时按 UTF-16 算，要切 Swift 字符串再用 `String.Index(utf16Offset:in:)` 转。

**测试**
- 所有测试文件在同一个测试目标里：一个文件顶层的 `let now`、`func task(…)`（没写 `private`）会和另一个文件的同名 `private` 声明冲突，报“invalid redeclaration”，而且是合并别人的分支之后才冒出来。测试里共用的造数据函数起不容易重的名字，自己文件里的都写 `private`。
- `#expect(…)` 里直接写带闭包的调用（`array.allSatisfy { … }`、`try` 的函数）会报“call can throw, but it is not marked with 'try'”。先算到一个 `let` 里再 `#expect`。
- 闭包参数会被后面的可选参数带成可选：`(0..<60).map { task("t\($0)", time: $0) }` 里 `time` 是 `Int?`，`$0` 就成了 `Int?`，标题变成“tOptional(1)”。写明参数类型 `{ (i: Int) in … }`。
- Swift Testing 默认并行跑，测试里给任务编号用的全局计数器要加锁（`Synchronization` 的 `Mutex`），否则编号会重复、排序断言偶尔失败。

**数据、通知、钥匙串**
- macOS 上数据保护钥匙串（`kSecUseDataProtectionKeychain`）要 `application-identifier` 权限，只有带描述文件的构建才有；没有描述文件的调试版读得出“没有这项”，写才报 -34018。所以判断钥匙串能不能用要试写一次（`KeychainTokenStore.isUsable`）；macOS 退到登录钥匙串（沙盒应用不用额外权限），`swift test` 里两个都不行，退到存库。
- GRDB 的挂起 / 恢复只有进程级的通知（`Database.suspendNotification`），会把同一进程里所有数据库一起挂起：单元测试里不能真挂起（会卡住同时在跑的别的测试），用 `AppLifecycle.Hooks` 记下调用；真挂起在应用里用 `-OTOpen selftest:suspend` 验。
- iOS 在后台挂起了数据库，通知按钮（完成、稍后提醒）把应用从后台唤起时，要先恢复数据库、开后台任务，写完、重排完提醒再挂起；`didReceive` 返回就是告诉系统处理完了，不能先返回再写。`AppServices.launch()` 要在 App 的初始化里调，从后台唤起时可能不建窗口，挂在视图的 `.task` 上就不会跑。
- `xcrun simctl privacy` 没有通知这一项，授不了通知权限；`.provisional` 授权不弹窗，自检用它。iOS 27 模拟器的通知服务有时不回应（`simctl push` 也卡住，抹掉重启也一样），自检里每个系统调用都加了超时。Mac 上调试版的通知可能在系统设置里被关着，这时只能验证排进系统，验证不了送达。
- 应用的 stdout 不是终端时有缓冲，被 `timeout` 杀掉或卡住时什么也看不到。自检（`selftest:` 路由）每行同时写进应用临时目录的 `selftest.log`。
- 同一个测试目标里，两个文件各写一个顶层的 `let now` 会报重复声明（`private` 的也和别的文件的非 private 冲突）；测试文件里的顶层常量起个带前缀的名字。
- `ScrollPosition`（`.scrollPosition` + `scrollTo(y:)`）在 macOS 上滚不动 `List`，偏移不变；`ScrollViewReader` 的 `scrollTo(id)` 可以。看板的自动滚动用前者（`ScrollView`），任务列表的按行用后者。
- 三栏 `NavigationSplitView` 没法只藏详情栏（`columnVisibility` 只能藏侧栏）。iPad 上看板和时间线要宽度时换成两栏，详情放 `.inspector`；两种结构切换时视图会重建（侧栏的滚动位置和宽度都丢）。Mac 上因此整个窗口只用一个两栏的分栏。
- macOS 的任务列表里，行上挂 `.draggable` 又直接挂 `.onGeometryChange`（拖放的落点要量每行的位置）时，单击不再选中这一行：系统列表的选中从没变过，任务打不开（11-27 用户报的）。拆开单挂哪一个都没事，玩具列表里两个一起挂也没事，只在真实的行上出现。现在量位置的是行背后一个同样大小的 `Color.clear`（`DropSlotModifier`）。`-OTOpen task:` 路由和辅助功能接口选中行都不经过点击，所以截图验收时没发现。
- iOS 的 `List`（底下是 `UICollectionView`）把拖到它上面的东西都留给自己：挂在整个列表上的 `.onDrop` 一次也收不到（日志里只有拖动开始），所以列表里拖了放不下、排不了序，这在 iPhone 和模拟器上都是一直如此，不是哪次改坏的（11-27 用户报的）。iPhone 上更早一步就不行：每行自己挂的 `.contextMenu` 把长按整个拿走，行连拖都拖不起来。iOS 上排序只能交给系统列表的 `ForEach.onMove`（只在同一个 `ForEach`、也就是同一个分组里移动），行不挂 `.draggable`。
  - `onMove` 平时一直开着的话，长按任意位置都会托起这一行，跟长按菜单抢：菜单挂在整个列表上（`.contextMenu(forSelectionType:)`）时两个能共存，但按住不动先出菜单、动了才拖，用户觉得冲突。现在 `onMove` 只在“排序”时给（列表进编辑模式，系统画 ≡ 把手，拖把手就行），平时长按就是菜单（行自己的 `.contextMenu`），长按行的右端进“排序”（`TaskListDrag.swift` 的 `taskRowMenu`）。编辑模式下列表的选中绑定要给 nil，不然每行前面出现多选圆圈。
  - 列表行的 `.contextMenu` 不看按在行的哪一块：在行上面盖一层带 SwiftUI `onLongPressGesture` 的透明视图，长按那里照样出菜单，长按手势也照样触发；按下时把菜单内容清空也挡不住，有时还是会弹出来。能挡住的是 UIKit 的 `UILongPressGestureRecognizer`（`UIViewRepresentable`）：在它的 delegate 里，`gestureRecognizer(_:shouldBeRequiredToFailBy:)` 对除了 `UIPanGestureRecognizer` 以外的都返回 true，菜单、托起、SwiftUI 的点按都等它失败才动。单击照样能打开任务（手指一抬它就失败），滚动不受影响。
  - XCUITest 里任务行这个元素是整行宽，右端那 64 点在行内容的最右边，再往右是列表的边距；按 `dx: 0.97` 会落在边距上，要按 `dx: 0.9`。系统把手的辅助功能标签是“对<行的标签>重新排序”（`UITestsIOS/Tasks/TaskListDragUITests.swift`）。
- 拖放：`DropDelegate` 只给指针位置，拿不到被拖的东西；`.draggable` 的 payload 是自动闭包，在拖动开始时才求值，`DragController` 就在这里记下拖的是什么。`onDragSessionUpdated`、`onDropSessionUpdated`、`dragContainer` 在 iOS 上要 27（macOS 26 就有），最低 iOS 26 时要 `#available`；iOS 26 拖到窗口外取消时没有结束通知，靠离开拖放区域或下一次拖动清状态。
- `Text + Text` 在 iOS 26 上弃用（编译警告），拼不同字体的文字改用插值：`Text("\(a)\(b)")`，`a`、`b` 都是 `Text`。
- 根视图把“一开始在哪一页”放在 `@State` 的初值里时，之后再传新的起点不起作用；要让已经显示着的模块重新打开到某一页（点通知、点“今天”里的条目），换一下它的 `.id(...)` 让它重建。
- `OpenTodoUI` 默认隔离在 `MainActor`，在这里给领域结构体写的扩展方法也是 `MainActor` 的，放进 `repo.updateTask(id) { … }` 这类 `@Sendable` 闭包里会报“main actor-isolated … in a synchronous nonisolated context”。这种辅助方法标 `nonisolated`。

**并行开发**
- 几个分支各自改 `RootView.swift`、`DebugLaunch.swift` 时用 union 方式合并，结果是两段 body 拼在一起、修饰器链里插进一段重复的视图，编不过或者跑起来不对。合并后要读一遍这两个文件；各功能尽量把自己的东西做成一个修饰器，在 `RootView` 里只加一行。
- 所有界面在同一个 SwiftPM 目标（`OpenTodoUI`）里：一个人的代码编不过，所有人的 `swift build`、`swift test` 和截图都跟着停。合并进 swift-native 前要在合并后的代码上跑一遍；新加的公开名字（类型、扩展方法）先搜一下有没有人用过。
- 别人还没合进来的部分先写替身时，名字和签名照抄真的，合并时删掉整个替身文件；替身和真的同时在时，本模块的声明会悄悄挡住导入的，所以一定要删。

**系统集成（App Group、扩展、菜单栏）**
- 加了 App Group entitlement 后，`xcodebuild -allowProvisioningUpdates` 会去开发者账号注册组、改 App ID、重做描述文件。`build.sh` 因此默认不带这个参数（`OT_ALLOW_PROVISIONING=1` 才带）；模拟器和 macOS 调试版（团队前缀的组）不需要它也编得过。
- GRDB 的观察只看得到经同一个连接池提交的改动：别的进程（小组件、分享扩展、快捷指令）写的、同一进程里另开的 `AppDatabase` 写的，都不会通知。所以一个进程只开一份 `AppServices`，别的进程写完发 `ChangeSignal`，由进程级的 `SystemSync` 重读给每个 `AppModel`。测试里用同一文件上的第二个连接池模拟“别的进程”。
- macOS 沙盒里 Darwin 通知（`CFNotificationCenterGetDarwinNotifyCenter`）的名字要以 App Group 开头才收发得到。
- 跟窗口走的东西（`.task`、`.onChange` 里起的观察和防抖）在窗口全关时就没了，而 macOS 上应用还开着菜单栏和快捷键。进程一直要做的事放进程级对象里，在 App 的 `init` 启动。
- macOS 上打开自己的 `opentodo://` 链接，`WindowGroup` 默认新开一个窗口；根视图加 `.handlesExternalEvents(preferring: ["*"], allowing: ["*"])` 才交给已有的窗口。
- 小组件扩展里领域层的类型会挡住 WidgetKit 的同名类型：`Timeline` 要写成 `WidgetKit.Timeline`；扩展里自己起的名字也别和 `OpenTodoSystem` 的撞（`HabitsWidget`）。
- WidgetKit 在 macOS 上没有 `accessory…` 尺寸，`supportedFamilies` 和判断尺寸的代码要 `#if os(iOS)`。`containerBackground` 的闭包要返回 View：渐变写成 `Rectangle().fill(color.gradient)`。
- `-OTSnapshot` 只画主窗口：popover、`MenuBarExtra`、`NSPanel` 都是单独的窗口，截不到。要看它们，用调试路由把同一个视图摆进主窗口（`system:`、`schedule:` 路由就是这么做的）。`Form` / `List` 关掉滚动（`.scrollDisabled(true)`）后自绘能画出内容。
- 脚本启动的调试版（带 `-OTDatabasePath`）不注册全局快捷键，否则截图时会抢走用户正在用的 ⌃⇧A。
- macOS 的 popover 里再弹 popover 会伸到窗口外面，也不像 Mac 应用；面板里的下一级改成在同一个面板里推入（带返回）。
- Swift Testing 的 `#expect(x.mutatingCall())` 编不过（宏里不能改值），先赋给变量再 `#expect`。
**状态放哪、测试**
- `AppModel` 一个窗口一份（Mac 多窗口、iPad 分屏就有好几份）。整个应用只能有一份、要自己跑的东西（专注计时器、到点记录、排通知）挂在 `AppServices` 上，窗口只显示和转发操作，否则每个窗口各算各的、重复写库。测试照样建两个 `AppModel` 共用一个 `AppServices` 来验证。
- 子模型自己默认用 `Date()` 当时钟、而服务用注入的时钟时，平时看不出来，固定时钟的测试里时刻对不上（记下的开始时间是真实的现在）。有共享的服务就用它的时钟。
- 测试文件顶层的 `private let now` 和别的测试文件里的同名 `internal` 常量冲突，报 “invalid redeclaration”（`private` 挡不住）。测试共用的造数据名字起得独特一些。
- 用 `sed` / `perl` 批量改测试里的变量名时会连字符串里的同一个词一起改（JSON 里的 `"today"` 变成了别的），改完搜一下引号里的。
- `UNUserNotificationCenter.current()` 在 `swift test`（没有应用包）里会崩。排通知的代码先看 `Bundle.main.bundleIdentifier`，或者把“排通知”做成可替换的闭包，测试里换掉。
- 提醒调度（`ReminderScheduler`）用数字 ID 排通知、只管数字 ID；自己另排的通知（比如专注结束）用固定的非数字 ID，重排前先按这个 ID 取消。
- 一次操作分两次写库（先添加、再置顶 / 归档）时，观察会先收到中间状态；测试要等最终状态（`waitUntil { 置顶了 }`），不能等“多了一条”。


**数据和同步**
- 同步引擎不管登录状态：退出登录（先删令牌再清库）时正在跑的同步会把旧账号的数据和游标一页页写回清空的库，换账号时会写进新账号。每个写库的事务里都要先确认令牌和 `account.userId` 没变（`SyncEngine.ensureStillSignedIn`），Flutter 版同样有这个问题。
- 在 GRDB 的写事务里再调用 `AppDatabase` 的方法（比如 `KeyValueTokenStore.token()`）会崩在“Database methods are not reentrant”。事务里要用传进来的 `Database` 直接读。
- `TimeZone.current` 是取值那一刻的快照，存进属性以后设备换了时区也不会跟着变，“今天”和提醒时刻就错了，要等重启。默认值用 `.autoupdatingCurrent`。
- Flutter 版（flutter_local_notifications）排的通知，任务 ID 在 `userInfo["payload"]`，标识是数字 ID 的字符串。升级后系统里还留着这些通知，处理点击和按钮时只读 `taskId` 会全部失效。
- 钥匙串里的令牌可能比库里的旧：钥匙串不随应用删除，可能还留着 Flutter 版退出、再用别的账号登录之前的令牌。搬令牌时以库里的为准；库里没有 `account.server` 时不算已登录。
- 拿真实库做测试时，只复制 `.sqlite` 会丢掉还在 `-wal` 里的最新数据。用只读方式（`?mode=ro`）打开再 `backup(to:)` 到临时目录，测试只打印数量。现成的测试是 `RealDatabaseTests`，要设 `OT_REAL_DB` 才跑。
- 要和 Dart 的实际输出对照（UUID v5、通知 ID）时，`app/` 里没跑过 `pub get` 的话 `dart run` 起不来。另建一个只依赖 `uuid` 的小 pub 包，`dart pub get --offline` 后就能跑；算出来的值写成测试的对照用例。
- 服务端遇到不认识的记录类型会让整次推送返回 400，连任务也同步不上。发布用了新记录类型的客户端之前，要先部署认得它的服务端。
