# Swift 版和 Flutter 版逐项对照（验收）

2026-11-26 验收：照 `docs/development.md` 第 1 节的表、`docs/roadmap.md` 打勾的条目、`docs/architecture.md` 的行为规则、`app/test/` 的界面测试，以及 Swift 版新加的功能（`docs/apple.md` 第 3、8、9 节），逐条在 `apple/` 里找实现、读代码、查调用方（确认从 `RootView` 走得到，回调落到 `TaskRepo` / `EfficiencyRepo` / `AppModel+Actions`，不只是调试路由），能测的看测试。

结论：

- **✅ 有且对**
- **🔧 已补**：验收时发现不对、没接上或者缺，已经改好并提交（每处一个提交，带测试的写了测试名）
- **⚠️ 有但不对**：问题还在，写清楚差在哪
- **❌ 没有**
- **❓ 待确认**：代码看着对，但只能在设备上手动确认（真实按键、手势、后台）

路径相对 `apple/OpenTodoKit/Sources/`。界面测试一栏写的是对应的 Swift 测试（`OpenTodoUITests` 等）。

## 汇总

| 区域 | ✅ | 🔧 | ⚠️ | ❌ | ❓ |
|---|---|---|---|---|---|
| 1. 任务模块核心、设置、搜索和过滤器 | 58 | 4 | 0 | 0 | 2 |
| 2. 分组、看板、排序、置顶、列表多选 | 48 | 8 | 0 | 0 | 2 |
| 3. 时间线 | 44 | 7 | 0 | 0 | 1 |
| 4. 日历 | 52 | 9 | 0 | 0 | 1 |
| 5. 提醒、重复、同步、账号 | 40 | 5 | 0 | 0 | 1 |
| 6. 效率模块、系统集成、图标 | 39 | 4 | 0 | 0 | 1 |
| **合计（326 行）** | **281** | **37** | **0** | **0** | **8** |

按任务书的三类算：**有且对 281 行**；**有但不对 / 没接上 / 没有 37 行，都已补上**：30 行是验收时直接补的（几处在两节里各列了一次，实际是 21 个提交），7 行是别人在验收期间补的（5 个提交，见下面）；另有 **8 行待确认**，要在设备上手动试（2026-11-26 收尾时仍没人在设备上按过，见下面“待确认的现状”）。对照表之外，跑应用时发现 macOS 上时间线会崩溃，之后一直没能复现（下面第 0 件）。

## 还没补的

0. ❓ **macOS：任务模块用时间线打开时，应用几秒后崩溃（没能复现）。** 当时的异常是 `NSGenericException`：“The window has been marked as needing another Update Constraints in Window pass, but it has already had more Update Constraints in Window passes than there are views in the window”，栈在 `SplitViewChildController … didUpdateMinSize`，也就是分栏的最小尺寸一直在变、布局停不下来。复现方法当时是 `OpenTodo -OTDatabasePath x/opentodo.sqlite -OTSeed demo -OTOpen timeline:list:work`（`timeline:smart:today` 一样），约 5–10 秒后退出；触发条件是时间线放在两栏 `NavigationSplitView` 的 detail 里（`Shell/TasksScreen.swift` 的 `wantsWidth` 那一支）。2026-11-26 收尾时在 swift-native 上（签名的调试版、屏幕锁着和没锁各一轮）把 `timeline:list:work`、`timeline:smart:today`、`board:@work/report`（看板 + 详情 inspector）在 1180×760 和 760×460 两种窗口下各后台跑了 80 秒，全都活着，`~/Library/Logs/DiagnosticReports` 里没有 OpenTodo 的崩溃报告；之前另一轮 42 个路由各 12 秒也都活着。推断是这期间别的修改（分栏宽度、时间线布局）顺带消掉了，但没找到是哪个提交，所以记为待确认：再出现时按上面的栈查。顺带查出并修了时间线常常打开在 2016 年的问题（eae4e09）。

验收时查出、太大没有直接补的另外 5 件，验收期间别人已经补好合进 swift-native，最后核对过代码和测试，表里记为 🔧：

1. iOS 后台按通知上的“完成”“稍后提醒”写不进库 → d008b26（`AppLifecycle`）
2. 日历在 Mac 窄窗口没有底部操作栏 → e1cc61c
3. 专注计时器每个窗口一份 → 5d29a73（`FocusTimerStore`）
4. 别的进程写了库以后菜单栏小窗不重读 → f58cdb9（`SystemSync`）
5. 看板和时间线上 ⌘A 不能全选 → 8e1ef54（`SelectAllShortcut`）

### 待确认的现状（2026-11-26 收尾）

8 行 ❓ 都还没在设备上确认。Mac 上的 4 行（对话框开着时的 ⌘F / ⌘N、列表行拖动和 ⌘ / Shift 点击、日历的单键和 ⌘A、没有窗口时点通知）要真的按键盘鼠标，收尾时用户正在用这台电脑，不能模拟输入，没有做；iPhone 上的 3 行（拖动清单排序、看板长按、时间线拖动时的自动滚动）要真机手势，模拟器里只跑了现有的界面测试（时间线长按拖动 3 个用例、冒烟测试 3 个用例，都过），不覆盖这几行；“开始专注”开始番茄还是正计时要用户定。

## 1. 任务模块核心、设置、搜索和过滤器

| 功能点 | 结论 | Swift 位置 / 说明 |
|---|---|---|
| 清单、任务、子任务的数据层 | ✅ | `OpenTodoData/TaskRepo.swift`（`addTask`、`deleteList` 连分组一起删） |
| 今天（含已过期） | ✅ | `OpenTodoDomain/Views.swift` `matchesView`；`ViewsTests` |
| 明天、最近7天（按天分组） | ✅ | `Views.swift` `byViewDay`、`buildSections` |
| 收集箱、已完成（按完成日分组）、垃圾桶 | ✅ | `Views.swift`；`ViewsTests` |
| 自建清单（emoji 图标，12 个和 Flutter 一样） | ✅ | `OpenTodoUI/Shell/DialogHost.swift` `ListEditorSheet` → `addList` / `updateList` |
| 标签视图（按清单分组） | ✅ | `Views.swift` `groupingsFor(.tag)`；`Tasks/ViewsList.swift` |
| 快速添加：中文日期时间、#标签、!优先级、重复、时间段 | ✅ | `OpenTodoDomain/QuickAddParser.swift`；`QuickAddParserTests`（Flutter 34 个全有） |
| 快速添加：输入时高亮、末尾显示识别出的日期 | ✅ | `Tasks/QuickAddField.swift` `highlight` / `preview` |
| 快速添加：带当前视图的默认值、有日期时加默认提醒、加到别处时提示 | ✅ | `Model/AppModel+Actions.swift` `quickAdd`；`Views.swift` `quickAddDefaults`；`AppModelTests.quickAddTakesTheViewsDefaultsAndSaysWhereItWent` |
| 详情：标题、备注（停 0.4 秒或离开时保存） | ✅ | `Tasks/TaskDetailView.swift` `scheduleSave` / `save` |
| 详情：日期一行（重复、提醒列在下面）、清单、优先级、置顶 | ✅ | `TaskDetailView.swift` |
| 详情：子任务（勾选、改名、删除、拖动、添加） | ✅ | `TaskDetailView.swift` `ChecklistSection`；`moveChecklistItem` |
| 详情：垃圾桶里只读，恢复 / 永久删除 | ✅ | `TaskDetailView.swift` `trashSection`；`trash` / `purge` 关掉详情 |
| 右键 / 长按菜单：改日期、优先级、移动、标签、置顶、副本、删除、多选 | ✅ | `Tasks/TaskMenu.swift`，列表、看板、时间线、日历、详情“更多”共用 |
| iOS 滑动：左滑完成，右滑删除 / 置顶 / 明天 | ✅ | `TaskMenu.swift` |
| 完成重复任务、删除、跳过此次后的提示和撤销（⌘Z 也行） | ✅ | `AppModel+Actions.swift`；`Model/Notices.swift`（登记 `UndoManager`） |
| 自适应布局：三栏 / 手机单栏 + 详情页 | ✅ | Mac：`Shell/MacShell.swift`（侧栏、列表、详情，详情能拖宽）；iPad / iPhone：`Shell/TasksScreen.swift`（`TasksSplitView` / `PhoneTasks`）；苹果做法，没有 Flutter 的“中屏两栏” |
| 默认值时机：快速添加（含日历新建框） | ✅ | `AppModel+Actions.swift` `quickAdd`（`settings.defaults.remindersFor`） |
| 默认值时机：右键菜单第一次给任务设日期 | ✅ | `TaskRepo.setDue` |
| 默认值时机：日期对话框给没日期的任务打开时 | ✅ | `Schedule/ScheduleEditor.swift` init；详情和 `DialogHost` 都传了 `settings.defaults` |
| 默认值时机：有时间 / 全天之间切换（对话框、拖动 `moveTo`） | ✅ | `ScheduleEditor.setTime`；`TaskRepo.moveTo` |
| 已有提醒的任务改日期不动提醒；`TaskRepo` 构造时注入默认值 | ✅ | `TaskRepo.swift`；`AppServices` 传 `settings.defaultsProvider` |
| 设置入口：Mac（设置窗口 ⌘,、侧栏底部账号行） | ✅ | `App/OpenTodoApp.swift`；`TasksScreen.swift` `AccountFooter` |
| 设置入口：iPhone（任务首页的齿轮） | ✅ | `TasksScreen.swift` `PhoneTasks`；Flutter 是抽屉里的“设置”，按苹果习惯改成齿轮 |
| 设置入口：iPad 全屏 | 🔧 | 原来宽屏的侧栏没有入口。现在任务侧栏顶上有“设置”（和总装的同一改动合并） |
| 过滤器字段和匹配（list、tag 含无标签、date 覆盖任一天、priority、keyword） | ✅ | `OpenTodoDomain/Filters.swift`；`FiltersTests` |
| 没选值的条件不参与；空规则 = 没进垃圾桶的全部 | ✅ | `Filters.swift` `isActive` / `matcher` |
| 删掉的清单显示“已删除的清单”，可取消勾选 | ✅ | `Filters/FilterEditorModel.swift` `filterValueOptions` |
| 不认识的字段原样保留，显示“新版本加的条件” | ✅ | `Filters.swift`；`Filters/FilterRuleEditor.swift` |
| 普通 / 高级，表达不了时“普通”变灰 | ✅ | `FilterEditorModel.canSimple` / `setAdvanced` |
| 过滤器视图分组（已过期 / 7 天 / 以后 / 无日期，已完成折叠） | ✅ | `Views.swift`；`FiltersTests` |
| 在过滤器里快速添加：用条件里的清单 / 日期 / 优先级 / 标签，不符合时提示 | ✅ | `Filters.swift` `quickAddHints`；`AppModel+Actions.swift` |
| 过滤器在侧栏、跟着账号同步 | ✅ | `Tasks/ViewsList.swift`；`OpenTodoData/Codec.swift` |
| 搜索：拆词（去开头 #），标题 / 描述 / 子任务 / 标签，垃圾桶不算 | ✅ | `OpenTodoDomain/Search.swift`；`SearchTests` |
| 搜索：清单、标签、过滤器按名字找 | ✅ | `Search.swift` |
| 搜索：排序、最多 100 个 | ✅ | `Search.swift`；`Search/SearchModel.swift` |
| 搜索：描述截一段（前 12 后 60）、列出子任务 / 标签 | ✅ | `Search.swift` `makeSnippet` |
| 搜索：命中的词标黄 | ✅ | `Search/SearchRows.swift` |
| 搜索：拼音输入还没上屏的字不参与 | ✅ | `SearchModel.committedText`；`SearchPanel` / `SearchPage` |
| 搜索：拼音和首字母找标题和名字 | ✅ | `Search.swift`；`PinyinTests` |
| ⌘F 打开搜索、↑↓ 选、回车打开 | ✅ | `Shell/AppCommands.swift` → `Search/SearchApp.swift`；`SearchPanel` `doCommandBy` |
| ⌘F / ⌘N 在对话框开着时不响应 | ❓ | `AppCommands` 只在没窗口时禁用；sheet 开着时按 ⌘F 可能把搜索浮层放到 sheet 后面。要在 Mac 上按一下 |
| 手机搜索是一整页 | ✅ | iOS 的“搜索”标签：`SearchApp.swift` `SearchScreen` |
| 点结果走 revealTask | ✅ | `Model/AppModel.swift` `revealTask`；`SearchApp.openSearchResult` |
| 最近搜索（`search.recent`，最多 10 条，不同步） | ✅ | `Search.swift` `RecentSearches`；`SearchApp.swift` 读写 |
| 描述里拼音搜索 | ✅ | `Search.swift`；`SearchExtrasTests` |
| 过滤器拖动排序 | ✅ | `ViewsList.swift` `onMove` → `Filters/FilterActions.swift` `moveFilter` |
| 过滤器日期“自定义范围”（`FilterDateRange`） | ✅ | `Filters.swift`；`Filters/FilterValuePicker.swift`，用在真实编辑器里 |
| 侧栏：智能清单、清单（+、编辑、删除先确认、拖动排序）、过滤器、标签、未完成数 | ✅ | `Tasks/ViewsList.swift`；`askDeleteList` / `moveList` |
| iPhone 上拖动清单排序 | ❓ | `ViewsList` 用 `.onMove`，视图列表页没有编辑按钮，和长按菜单抢手势，要在设备上试 |
| 列表：显示选项（分组 / 排序 / 布局）存 `key_values`，显示已完成只在这个窗口 | ✅ | `Tasks/TaskListArea.swift` `ViewOptionsMenu` |
| 列表：分组折叠、空日子灰色、垃圾桶清空和说明 | ✅ | `Tasks/TaskListView.swift` |
| 菜单：文件、编辑、显示、前往、清单 | ✅ | `Shell/AppCommands.swift` |
| 菜单：任务（完成、日期、优先级、置顶、跳过、副本；多选时对所选的；日历里对日历打开的任务） | ✅ | `AppCommands.swift`（日历那条是总装补的） |
| 菜单：删除 ⌘⌫ | 🔧 | 菜单比输入框先拿到 ⌘⌫，在标题、备注或快速添加框里按“删到行首”会把打开的任务扔进垃圾桶。现在输入框有焦点时把 ⌘⌫ 交给输入框 |
| 日期对话框：系统通知被关时提示“去开启” | 🔧 | 控件早就有，但详情和右键菜单两个调用方都没传 `notificationsAllowed`。现在都接上了（`AppModel.notificationsAllowed` / `openNotificationSettings`） |
| 新建任务（⌘N / 工具栏 +）在时间线、看板上 | 🔧 | 原来宽屏只让列表顶上的输入框获得焦点，时间线和看板上没有这个框，按了没反应。现在时间线顶上有快速添加框（Flutter 一样），看板弹出快速添加；`AppModelTests.newTaskGoesToTheFieldOrTheSheet` |
| app_test：桌面添加、打开、完成 | ✅ | `AppModelTests`（空状态文案、预览“今天, 下午3:00”、标签、勾选） |
| app_test：日期对话框设时间段 | ✅ | `ScheduleEditorTests`；`AppModelTests` |
| app_test：设置里的默认提醒 | ✅ | `AppModelTests`；`ScheduleEditorTests`；`Settings/SettingsSections.swift` |
| app_test：手机的设置入口 | ✅ | `AppModelTests`（路由）；齿轮在 `PhoneTasks` |
| app_test：手机列表和详情页 | ✅ | `AppModelTests`；iPhone 的 + 是 `QuickAddSheet` |
| app_test：过期标红（列表和详情） | ✅ | `Components/DueLabel.swift`；`GroupHeader` `alert`；`AppModelTests` |
| search_filter_ui_test 4 个用例（建过滤器、在里面添加、改高级、删除回今天；别处删掉正看着的；⌘F 搜索和片段；手机搜索页） | ✅ | `SearchFilterAppTests`；iOS 的 `SearchFilterUITests` |

小出入（不改）：Mac 的放大镜只在任务模块工具栏，其他模块用 ⌘F；iPhone 视图列表页没有 +（要先进一个视图）；编辑没有 emoji 的清单时不默认 📋；“跳过此次”在右键菜单里只对未完成的显示。

## 2. 分组、看板、排序、置顶、列表多选

| 功能点 | 结论 | Swift 位置 / 说明 |
|---|---|---|
| 清单（含收集箱）里加分组 | ✅ | `TaskListArea.swift` 显示选项“添加分组”；`Board/BoardView.swift`；`askAddSection` |
| 列表里分组是标题，没有分组时不显示标题 | ✅ | `TaskListView.swift`；`Views.swift` `listGroups` |
| “未分组”在最前，只在有任务或清单还没有分组时出现；空分组也显示 | ✅ | `Views.swift` `listGroups`（和 `views.dart` 逐行一致） |
| 分组标题 ⋯：重命名、上移、下移、删除（先确认） | ✅ | `TaskListView.swift`；`AppModel+Actions.swift`（上移下移用 `planMove`） |
| 看板：每个分组一列，接进了应用 | ✅ | `TaskListArea.swift` `LayoutContent` → `Board/BoardHost.swift` `ListBoard`，回调进 `dropInto` / `quickAdd` / `setDone` |
| 看板列头 + 在这一列里添加 | ✅ | `BoardView.swift` → `quickAdd(target: listId + sectionId)` |
| 已完成折叠在列底、不能拖 | ✅ | `BoardView.swift` |
| 看板最右边“添加分组”；空列“拖任务到这里” | ✅ | `BoardView.swift` |
| 看板时顶上的输入框不显示 | ✅ | 看板没有顶上的框；⌘N 见第 1 节（已补） |
| 宽屏看板的详情栏只在选中任务时出现 | ✅ | `TasksScreen.swift`（inspector） |
| 宽屏看板的详情栏可以关 | 🔧 | 原来没有关闭按钮。现在详情栏工具栏有“关闭详情” |
| 布局和排序每台设备、每个清单各自存，旧格式读得出 | ✅ | `OpenTodoData/Settings.swift`（`list.layouts`） |
| 排序方式：自定义 / 时间 / 标题 / 标签 / 优先级，只有清单能自定义 | ✅ | `Views.swift` `sortsFor`；`ViewOptionsMenu` |
| 按标题排序（拼音，中英文一起） | ✅ | `Views.swift` `compareByTitle` → `Pinyin.swift` |
| 分组方式：每个视图各自一套 | ✅ | `Views.swift` `groupingsFor`；Flutter 的 ⇅ 和 ⋯ 合成了一个“显示选项” |
| 看板的列始终是自定义分组；添加分组时切回自定义分组 | ✅ | `TaskListArea.swift`；`AppModel+Actions.swift`、`BoardHost.swift` |
| 拖进一组就改成那组的日期 / 优先级 / 清单 / 标签 | ✅ | `TaskRepo.dropInto` / `takeOn`；`BoardDragTests` |
| 置顶（菜单、滑动、详情、⇧⌘P），同组里置顶的在前，重复任务的副本不带置顶 | ✅ | `TaskMenu.swift`；`Views.swift` `pinnedFirst`；`TaskRepo.swift` |
| 列表里拖动排序、拖到别的分组 | ✅ | `Drag/TaskListDrag.swift`（用在 `TaskListView`，不只是 `DragListDemo`） |
| 放在上半部分到前面、下半部分到后面，有一条线 | ✅ | `Drag/DropGeometry.swift` |
| 放到分组标题上是第一个，放到看板列空白处是最后一个 | ✅ | `TaskListDrag.swift`；`BoardView.swift` |
| 不是自定义排序时只换分组（整组变色、不画线） | ✅ | `Drag/DragItems.swift` `accepts`；`DropGeometry.swift` |
| 只能在同一个清单里拖；已完成的不能拖 | ✅ | `Views.swift` `GroupTarget.takes`；`DragItems.swift` `movable` |
| 拖到边上自动滚动（列表、看板横向和列里纵向） | ✅ | `TaskListDrag.swift`；`BoardView.swift` |
| `planMove`：只改一行、挤不下按 1024 重排、放回原处不写、置顶只在置顶里排 | ✅ | `OpenTodoDomain/Ordering.swift`；`OrderingTests` |
| 今天 / 明天 / 最近7天拖到别的日子改期（时间不变、整段移动，已过期不能往里放） | ✅ | `takeOn .date` → `moveTo`；`BoardAppTests` |
| 最近7天里没有任务的日子也显示 | ✅ | `TaskListView.swift`；`AppModelTests.next7ShowsEveryDayEvenEmptyOnes` |
| 多选后一起拖 | ✅ | `TaskListDrag.swift`；`Board/BoardModel.swift` |
| 一起拖时折叠的分组里选中的不跟着走 | 🔧 | 原来会一起拖走。现在照 Flutter 的 `picked` 排除；`BoardAppTests.thePickedRowsInTheOrderShownAndTheRowsToScrollBy` |
| 拖动分组本身（列表拖标题、看板拖列顶） | ✅ | `TaskListDrag.swift`；`BoardView.swift`。小出入：列表里只有标题接受放下，Flutter 是整个分组块 |
| 多选：⌘ 点选，第一次带上正开着的任务 | ✅ | `Tasks/TaskListPicking.swift`（系统 List 多选）；看板 `BoardHost.swift` |
| 多选：没有打开的任务时 ⌘ 点一下进多选 | 🔧 | 原来只是打开它。现在和 Flutter 的 `tapTask` 一样进多选 |
| 多选：Shift 按屏幕顺序连选（折叠分组不算，看板按列） | ✅ | 系统 List；`AppModel+Batch.swift` `shownOrder`；`BoardModel.taskOrder` |
| 多选：⌘A（光标在输入框里时不管）——列表 | ✅ | 系统 List 的全选 |
| 多选：⌘A——看板 | 🔧 | 原来没有处理。验收期间 8e1ef54 补上（`Board/SelectAllShortcut.swift`，输入框有焦点时留给输入框；`BoardAppTests`） |
| 多选：垃圾桶里 ⌘A | 🔧 | 原来会随手打开一个任务。现在什么都不做；`AppModelTests.inTheTrashSelectAllPicksAndOpensNothing` |
| 多选：Esc 取消 | 🔧 | 原来只挂在列表上，看板和时间线里不起作用。现在挂在列表区域外层，三种布局都有 |
| 多选：换视图、换模块时清空 | ✅ | `AppModel.select` / `switchTo` |
| 多选：iPhone 经导航返回再打开别的视图时清空 | 🔧 | 原来 `phonePathChanged` 不清，B 清单会直接进编辑模式。现在清空；`AppModelTests.aPhoneOpeningAnotherViewStopsPicking` |
| 多选：手机长按菜单“多选”进入，之后点一下选一个，“完成”退出 | ✅ | `TaskMenu.swift`；`TaskListPicking.swift` |
| 多选：iPhone 底部操作栏，这时不显示加号——列表 | ✅ | `TaskListPicking.swift`；`TaskListArea.swift` |
| 多选：iPhone 底部操作栏——看板、时间线 | 🔧 | 原来只挂在列表上，看板和时间线进了多选没有操作栏也退不出来。现在三种布局共用 |
| 多选：宽屏右边换成批量面板 | ✅ | `TasksScreen.swift` `BatchDetail` |
| 垃圾桶里不能多选 | ✅ | `AppModel+Batch.swift` `canPick` |
| 批量改日期保留每个任务的时间；改优先级、移清单 | ✅ | `Batch/BatchModel.swift`；`AppModel+Batch.swift`；`BatchModelTests` |
| 批量标签三态 | ✅ | `BatchModel.swift` `BatchTagsEditor` |
| 批量完成和删除后清空选择、可撤销 | ✅ | `AppModel+Batch.swift`；`AppModelTests` |
| 批量置顶规则、复制标题每行一个 | ✅ | `BatchModel.swift`；`Batch/BatchViews.swift` |
| board_ui_test 1：列表里拖进分组、分组里排、重命名删除分组 | ✅ | `BoardDragTests`；`AppModelTests.sectionsAddRenameMoveDelete`；`BoardAppTests` |
| board_ui_test 2：看板跨列拖、列里添加、勾掉进已完成、切回列表 | ✅ | `BoardDragTests`；`BoardAppTests` |
| board_ui_test 3：最近7天拖到别的日子（含空日子），保留时间 | ✅ | `BoardDragTests`；`BoardAppTests` |
| board_ui_test 4：一起拖、拖分组标题、看板拖列 | ✅ | `BoardDragTests` |
| board_ui_test 5：置顶、按优先级时只换分组、从详情取消置顶 | ✅ | `BoardDragTests`；`BoardAppTests` |
| board_ui_test 6：手机长按不动出菜单、长按移动是拖动 | ❓ | 系统 `.contextMenu` 加 `.onDrag`，只有落点的测试，要在设备上试 |
| board_ui_test 7：按优先级 / 标签 / 时间分组后拖动；添加分组切回 | ✅ | `BoardDragTests`；`BoardAppTests` |
| board_ui_test 8：今天按清单分组、拖到别的清单、不分组 | ✅ | `BoardDragTests`；`BoardAppTests` |
| selection_test | ✅ | `SelectionTests`；`AppModelTests` 的选择和批量用例 |
| macOS 列表行同时有 `.onDrag` 和系统多选时 ⌘ / Shift 点击 | ❓ | 只有模型层测试，要在 Mac 上点一下 |

## 3. 时间线

| 功能点 | 结论 | Swift 位置 / 说明 |
|---|---|---|
| 接进应用：`LayoutContent` 的 `.timeline` → `TaskTimeline`，回调进 TaskRepo / AppModel | ✅ | `Timeline/TaskTimeline.swift`；`Timeline/AppModel+Timeline.swift` `applyTimelineEdit`。`TimelineDemo` 只给调试路由 |
| ⋯ 里选“时间线”，每台设备每个视图各选各的（⌃⌘3） | ✅ | `TaskListArea.swift` `layouts(for:)`；`Settings.swift` |
| 按日期画横条，跨天画到结束 | ✅ | `OpenTodoDomain/Timeline.swift` `TimelineBar` |
| 挤不下往下排 | ✅ | `Timeline.swift` `packRows` |
| 分组泳道（清单按分组） | ✅ | `Timeline.swift` `buildTimeline` |
| 日 / 周 / 月缩放（换档时保留左边那天） | ✅ | `Timeline/TimelineView.swift`；`TimelineLayout.swift` `offsetAfterScaleChange` |
| 左右无限滚动 | ✅ | `TimelineLayout.swift` |
| “今天”、往前 / 往后 | ✅ | `TimelineView.swift` `goHome` / `page` |
| 当前时刻的红线 | ✅ | `TimelineView.swift` `TimelineNowLine` |
| 周末和法定假日加底色 | ✅ | `Timeline/TimelineCanvas.swift` `isDayOff` |
| 拖动改日期（保留时间和时长） | ✅ | `TimelineView.endDrag` → `repo.placeOnTimeline` |
| 多选的一起拖 | ✅ | `TimelineView.swift` |
| 拖进别的泳道换分组 | ✅ | `TimelineLayout.swift` `landing` / `placement`；`TaskRepo.takeOn` |
| 拖右边缘改结束 | ✅ | `TimelineLayout.resizeEdit` → `repo.setDuration` |
| 拖左边缘改开始（结束不变；计时任务保留几点开始，开始晚于结束时去掉时长） | ✅ | `Timeline.swift` `restartedSchedule` → `repo.setStart`；`TimelineTests` |
| 点空白新建 | ✅ | `TimelineView.swift` → `TimelineNewTaskSheet`（`QuickAddField`） |
| 点空白新建的对话框里换清单（换了就不带泳道的分组） | 🔧 | 原来只显示一行文字，不能换。现在有清单选择，和日历的新建框一样 |
| “无日期”一栏拖上时间线、拖回来去掉日期 | ✅ | `TimelineCanvas.swift` `TimelineTray`；`.unschedule` → `repo.dropInto` |
| 无日期一栏宽屏在旁边、窄屏在下面默认收起 | ✅ | `TimelineView.swift` |
| 显示已完成（完成的不能拖、没有拖边缘） | ✅ | `TimelineView.swift`；`Timeline.swift` `shows` |
| 手机：长按两头拖改开始 / 结束 | ✅ | `TimelineView.swift`；iOS `TimelineDragUITests.testLongPressOnTheEndDragsTheEnd` |
| 手机：中间长按整条拖 | ✅ | `Timeline/TimelineParts.swift` `PressDrag`；iOS `testLongPressThenDragMovesABar` |
| 手机：长按不动出菜单——未完成的 | ✅ | `PressDrag.onStill`；iOS `testLongPressWithoutMovingOpensTheMenu` |
| 手机：长按不动出菜单——已完成的 | 🔧 | 原来完成的横条整个关掉了 `PressDrag`，长按没有菜单。现在单独接一个长按出菜单 |
| 点一下勾选、打开；多选时点一下是选 | ✅ | `AppModel+Timeline.swift` `tapOnTimeline`；勾选走 `model.setDone` |
| 拖边缘时的日期提示不出屏 | ✅ | `TimelineView.swift` |
| 今天 / 明天 / 最近7天 / 标签 / 过滤器也能用时间线 | ✅ | `layouts(for:)`；`Timeline.swift` `buildViewTimeline` |
| 泳道按视图的分组，不按时间，默认按清单 | ✅ | `Views.swift` `timelineGroupingsFor`；`Settings.swift` `timelineGroupingIn` |
| 拖进泳道改清单 / 标签 / 优先级 | ✅ | `TaskRepo.placeOnTimeline`；`TaskRepoTests.placeOnTimeline` |
| 组里有任务就有泳道，空视图也有一条 | ✅ | `Timeline.swift` |
| 今天 / 明天 / 最近7天没有“无日期” | ✅ | `TimelineView.swift` |
| 点空白新建只在视图显示的日子上有效 | ✅ | `TimelineView.swift` `dateViewShows` |
| 新建的任务带上泳道的清单 / 分组 / 标签 / 优先级 | ✅ | `Timeline.swift` `laneNewTask` |
| 折叠泳道 | ✅ | `TimelineView.swift` |
| 选中的横条颜色加深、加边框 | ✅ | `TimelineParts.swift` |
| 时间线上方的快速添加框，⌘N / 工具栏 + | 🔧 | 见第 1 节 |
| 多选：Mac 批量面板 | ✅ | `TasksScreen.swift` `BatchDetail` |
| 多选：iPhone 底部操作栏和“完成” | 🔧 | 见第 2 节 |
| 多选：Esc | 🔧 | 见第 2 节 |
| 多选：⌘A | 🔧 | 同上，8e1ef54（时间线也挂了 `SelectAllShortcut`） |
| Swift 新加：拖到屏幕边自动滚动（横条、边缘，横向和纵向） | ✅ | `TimelineView.swift` `autoScroll`；`TimelineLayout.swift` `autoScrollStep` |
| iOS 拖动时 `.scrollDisabled` 和自动滚动一起用 | ❓ | 只有步长函数的单测，要在设备上看 |
| Swift 新加：横条开头滚出屏幕时标题留在左边 | ✅ | `TimelineLayout.swift` `stickyTitleOffset`（泳道标题也贴左） |
| Swift 新加：今天的时间线能看到最早的过期任务 | ✅ | `TimelineView.swift` `homeOffset`；`TimelineLayout.swift` |
| 同上：启动时直接打开今天的时间线（数据还没到） | 🔧 | 原来起始位置只在数据到之前算一次，算不到过期任务。现在数据到了以后重新算 |
| timeline_ui_test 1：拖日期、保留时间、无日期拖进拖出、拖右边缘、拖左边缘和提示 | ✅ | `TimelineAppTests.moveAndStretch`；`TimelineLayoutTests` |
| timeline_ui_test 2：今天按清单分泳道、拖进别的清单、只有今天能新建、没有按时间、不分组；标签视图从无日期拖上来 | ✅ | `TimelineAppTests.todayAndTag` |
| timeline_ui_test 3：分组泳道、点空白新建、⌘ 点选一起拖、Esc、缩放 / 往后 / 今天、折叠 | ✅ | `TimelineAppTests.sectionsAndPicking`（Esc 已补到界面上） |
| timeline_ui_test 4：显示已完成 | ✅ | `TimelineAppTests.finished` |
| timeline_ui_test 5：手机长按拖动、无日期在下面展开 | ✅ | iOS `TimelineDragUITests` |
| timeline_ui_test 6：手机长按两头、长按不动出菜单、点头上的勾选框 | ✅ | iOS `TimelineDragUITests`；左端只有单测 |
| timeline_test.dart（含两个 repo 用例） | ✅ | `TimelineTests`；`TaskRepoTests.placeOnTimeline` / `setStart` |

## 4. 日历

| 功能点 | 结论 | Swift 位置 / 说明 |
|---|---|---|
| 接进应用：`CalendarScreen` 用 `Calendar/CalendarView`，写操作都接上 | ✅ | `Shell/CalendarScreen.swift`；`Calendar/CalendarWiring.swift` `calendarActions`（改期 `moveAll`、改时长 `setDuration`、勾选 `setDone`、新建 `quickAdd`、批量 `applyBatch`）。`CalendarDemo` 只给调试路由 |
| 月 / 周 / 3 天 / 日 / 日程 | ✅ | `CalendarView.swift`；`MonthBoard`、`TimeGrid`、日程 |
| 模块切换（Mac 侧栏里的行、iOS 标签），切换时清空多选 | ✅ | `Shell/MacShell.swift`、`Shell/ModuleScreen.swift`；`AppModel.switchTo` / `choose` |
| visibleRange（周、月从周一开始，月补齐整周，日程是当月） | ✅ | `OpenTodoDomain/Calendar.swift`；`CalendarTests` |
| 上下页，按月翻时尽量保留几号 | ✅ | `Calendar.swift`；`Day.addingMonths` |
| calendarEntries（有日期、没进垃圾桶、清单没隐藏、已完成可隐藏） | ✅ | `Calendar.swift` |
| 重复任务展开以后的日期（COUNT / UNTIL，只在今天以后） | ✅ | `Calendar.swift` `calendarEntries` |
| 预计条目不能勾选、不能拖，点开是任务本身 | ✅ | `Calendar/CalendarChips.swift`；`CalendarInteraction.swift` `canMoveEntry` |
| 每小时 48 点；跨午夜分截；一个时刻按 30 分钟画；重叠分列 | ✅ | `CalendarInteraction.swift`；`Calendar.swift` `layoutTimed` |
| 全天栏（1 天最多 6 行、几天最多 3 行，“+N”打开那天） | ✅ | `Calendar/TimeGrid.swift`。文字是“+N”，Flutter 是“还有N项”（无障碍标签用后者） |
| 拖动改日期（月格子） | ✅ | `Calendar/MonthBoard.swift` → `dropTargets` → `calendarMove` |
| 拖动改时间，吸附 15 分钟 | ✅ | `TimeGrid.swift`；`CalendarLogic.dropMinute` |
| 拖进“全天”去掉时间 | ✅ | `TimeGrid.swift` |
| 时间段整段移动（dropTarget） | ✅ | `Calendar.swift` `dropTarget` |
| 有时间 / 全天之间切换时提醒重置 | ✅ | `TaskRepo.moveTo` |
| 拖下边缘改结束（没有时间段的也能拖出一个） | ✅ | `CalendarChips.swift` `ResizeHandle` → `calendarSetDuration` |
| 点空白新建：月格子是全天，小时格是点到的半小时 | ✅ | `Calendar/CalendarParts.swift`；`TimeGrid.swift` |
| 新建框是快速添加，识别输入的日期，可换清单 | ✅ | `CalendarWiring.swift` `CalendarQuickAdd` |
| 电脑工具栏 + 的默认日期 | ✅ | `CalendarInteraction.swift` `defaultNewDay` |
| 手机 + 加到小月历里选中的那天 | 🔧 | 原来这个月里有今天就加到今天。现在手机上总是选中的那天；`CalendarInteractionTests.defaultNewDay` |
| 按清单筛选（iPad 侧栏；Mac 和手机在“更多”里） | ✅ | `Calendar/CalendarSidebar.swift`；`CalendarView.swift`。Mac 的侧栏是整个窗口的，不再换成日历的那套（2026-11-27） |
| 农历、节日、休 / 班标注 | ✅ | `CalendarParts.swift` `CalendarDayNote`；`Calendar.swift` `dayNote` |
| 显示已完成 / 重复以后的日期 / 农历的开关——侧栏 | ✅ | `CalendarSidebar.swift` |
| 同上——电脑“更多”里 | 🔧 | 原来电脑上只在侧栏里有，收起侧栏就找不到。现在“更多”里也有（Flutter 一样） |
| 键盘 D 3 W M A（另加 Y）、T、← → | ✅ | `CalendarView.swift` `handle`；`CalendarInteractionTests.keys` |
| 单键、⌘A、Esc 在真实窗口里（焦点在别处之后） | ❓ | `CalendarView` 用 `.focusable` + `onKeyPress`，只在出现时拿一次焦点；⌘A 可能先被“编辑 › 全选”拿走。要在 Mac 上按一遍 |
| 宽屏侧栏：小月历、要显示的清单 | ✅ | iPad：`CalendarSidebar.swift`。Mac：小月历在窗口侧栏的底部（`CalendarMonthJumper`，日历在屏幕上时），要显示的清单在“更多”里 |
| 宽屏侧栏：账号 | 🔧 | 原来日历侧栏底部没有账号行。现在和任务模块一样 |
| 侧栏小月历的点跟着过滤器 | 🔧 | 原来按全部任务画点。现在先过选中的过滤器（`shownTasks`） |
| 手机月视图：小月历加当天列表，左右滑翻月 | ✅ | `Calendar/CalendarMonths.swift` `PhoneMonth` |
| 点任务在右边开详情，手机推一页 | ✅ | `CalendarScreen.swift` |
| 模式和选项存 `calendar.prefs` | ✅ | `CalendarWiring.swift`；`OpenTodoDomain/CalendarPrefs.swift` |
| 多选：⌘ 点选（第一次带上开着的）、Shift 按显示顺序、⌘A 选这一页、Esc | ✅ | `CalendarChips.swift`；`Calendar.swift` `calendarOrder`；`CalendarWiring.swift` `pageOrder` |
| 多选：宽屏批量面板 | ✅ | `CalendarScreen.swift` `BatchPanel` |
| 多选：Mac 窄窗口底部操作栏、中屏推详情 | 🔧 | 原来一律在右边放面板。验收期间 e1cc61c 补上：不够宽时批量操作在底部 `BatchBar`、详情用 sheet；`CalendarInteractionTests` |
| 多选：手机底部操作栏 | ✅ | `CalendarScreen.swift` `batchBottomBar` |
| 多选：手机选着时不显示加号 | 🔧 | 原来一直显示。现在和任务列表一样藏起来 |
| 多选：选着时点空白是取消选择 | ✅ | `CalendarParts.swift` |
| 多选：手机长按菜单“多选”，之后点一下选一个 | ✅ | `CalendarChips.swift`；`SelectionModel` |
| 一起拖：月格子挪同样天数；小时格挪同样分钟；带头全天 / 计时的各种情况；已完成 / 垃圾桶 / 无日期的不动 | ✅ | `Calendar.swift` `dropTargets`；`CalendarTests` |
| 拖动中其他选中的变淡、带数字，悬停“11:00 · 3 项” | ✅ | `CalendarChips.swift`；`TimeGrid.swift`；`CalendarInteractionTests.hover` |
| 选中的条颜色加深、加边框 | ✅ | `CalendarChips.swift` `ChipStyle` |
| 任务菜单（⌘↩、⌘⌫…）对日历里打开的任务 | ✅ | 总装补的（`AppCommands`） |
| Swift 新加：年视图 | ✅ | `CalendarMonths.swift` `YearView`（键 Y，点一天进日视图） |
| Swift 新加：多周（2–6 周） | ✅ | `MonthBoard`；“更多”里选周数 |
| Swift 新加：“安排任务”面板 | ✅ | `CalendarSidebar.swift` `ArrangePanel` → `calendarMove`；手机点一下排到选中那天 |
| Swift 新加：任务卡片 | ✅ | `Calendar/TaskCard.swift`；“更多 › 点任务时” |
| Swift 新加：跨天整条（月视图、多周、全天栏） | ✅ | `OpenTodoDomain/CalendarExtras.swift` `weekLayout`；`MonthBoard.swift` |
| Swift 新加：日历里按过滤器筛 | ✅ | `CalendarWiring.swift` `shownTasks`；`CalendarFilterPicker` |
| calendar_ui_test 1：各模式、点开详情和关闭、模式菜单、键盘、模式记住、切回任务 | ✅ | `CalendarScreenTests`；`CalendarInteractionTests.keys` |
| calendar_ui_test 2：拖到别的天保留时间和提醒；点格子新建全天 | ✅ | `CalendarScreenTests` |
| calendar_ui_test 3：周视图拖两小时、进全天、点 14:00 新建带准时提醒 | ✅ | `CalendarScreenTests.weekMoves` |
| calendar_ui_test 4：时间段高度、拖下边缘、整段移动 | ✅ | `CalendarScreenTests.bottomEdge` |
| calendar_ui_test 5：跨天的时间段每天都出现 | ✅ | 数据上每天一个条目（`dayIndex`）；全天栏画成一整条，是“跨天整条”有意的改动 |
| calendar_ui_test 6：农历显示并可关 | ✅ | `CalendarScreenTests` |
| calendar_ui_test 7：重复任务以后的日期带图标、点开是任务本身、可关 | ✅ | `CalendarScreenTests` |
| calendar_ui_test 8：手机小月历加当天列表、+ 加到选中那天、点开推一页 | 🔧 | + 的日期已补，其余本来就对 |
| calendar_selection_test 1：月视图点选、批量面板、一起拖、点空白取消、⌘A、Esc、Shift、批量完成 | ✅ | `CalendarScreenTests.picking`；`CalendarTests` |
| calendar_selection_test 2：周视图同样分钟数、悬停提示、进全天 | ✅ | `CalendarTests`；`CalendarInteractionTests.hover` |
| calendar_selection_test 3：窄窗口底部操作栏改优先级 | 🔧 | 同上，e1cc61c |
| calendar_selection_test 4：手机菜单进多选、点选、批量完成、加号隐藏、长按不动不改时间、长按拖动 | 🔧 | 加号已补；长按手势靠系统 `contextMenu` / `onDrag`，没在设备上试 |
| calendar_test.dart 全部用例 | ✅ | `CalendarTests` 一一对应 |

## 5. 提醒、重复、日期对话框、同步、账号

| 功能点 | 结论 | Swift 位置 / 说明 |
|---|---|---|
| 邮箱注册登录、服务器地址 | ✅ | `OpenTodoData/Account.swift`；`OpenTodoUI/Account/AccountBound.swift` |
| 登录限流等错误文案 | ✅ | `Account.swift`（和 `account.dart` 逐条一样） |
| 自动同步：改动 2 秒后、每分钟、回前台 | ✅ | `OpenTodoData/SyncController.swift`；`AppServices.appDidBecomeActive` |
| 新者胜；先应用拉回的再标记推送成功（同一事务） | ✅ | `OpenTodoData/SyncEngine.swift` |
| 推送期间又改过的行不标记 | ✅ | `SyncEngine.swift`（`WHERE updated_at = ?`） |
| 删除标记推送后物理删除、hasMore 翻页 | ✅ | `SyncEngine.swift` |
| 首次登录合并本地数据，丢掉没动过的欢迎任务 | ✅ | `SyncEngine.swift`；`TaskRepo.seedIfEmpty` |
| 退出登录清空本机（连令牌） | ✅ | `SyncEngine.swift` |
| 同步状态显示（Mac 侧栏底部、设置） | ✅ | `AccountSidebarItem`；`AccountSettingsRow`；`AccountPane` |
| 令牌存钥匙串，第一次启动从 `account.token` 搬过去并删掉 | ✅ | `OpenTodoData/TokenStore.swift`；`AppServices.launch`。macOS 没有数据保护钥匙串时用登录钥匙串（data 补的） |
| `AppServices.launch()` 用系统通知和钥匙串 | ✅ | `AppServices.swift`；`Model/AppLaunch.swift` |
| 本地通知：准时、提前 N、全天某个时刻、自定义、多个 | ✅ | `OpenTodoDomain/Reminders.swift`；`Schedule/ReminderChoices.swift`、`SchedulePages.swift` |
| 调度：防抖 0.5 秒、回前台、每 15 分钟、48 个、只动变了的 | ✅ | `OpenTodoData/ReminderController.swift`；`ReminderScheduler.swift` |
| 通知 ID 由任务 ID 和触发分钟算 | ✅ | `Reminders.swift` `notificationId` |
| 权限第一次真有提醒要排时才申请；被拒后回前台重查 | ✅ | `ReminderScheduler.swift`；`ReminderController.appDidBecomeActive` |
| 权限被拒：设置页提示去开启 | ✅ | `Settings/SettingsOptions.swift`；`OpenTodoSettingsView.swift` |
| 权限被拒：日期对话框提示去开启 | 🔧 | 见第 1 节 |
| 点通知打开任务（应用开着） | ✅ | `ReminderController.respond` → `openRequest` → `RootView` → `model.handle` → `revealTask` |
| 点通知打开任务（被通知唤起） | 🔧 | 原来 delegate 要等窗口的 `.task` 才设上，启动用的那个通知可能丢。现在 `AppServices.launch` 时就设好（`SystemReminderBackend.listenEarly`），在提醒调度启动前收到的先存着 |
| 通知上的“完成”（去掉稍后提醒）、“稍后提醒”——应用在前台 | ✅ | `OpenTodoData/ReminderActions.swift`；`ReminderTests` |
| 同上——iOS 应用在后台 | 🔧 | 原来后台时数据库是挂起的，按钮写不进。验收期间 d008b26 补上（`OpenTodoData/AppLifecycle.swift`：处理按钮时恢复、后台任务包住、写完再挂起；回调等处理完才返回；`AppLifecycleTests`）。真机上还没按过 |
| 稍后提醒存 `reminders.snoozed`，过期的清掉；时长在设置里 | ✅ | `ReminderActions.swift`；`Settings/SettingsSections.swift` |
| 通知格式版本号 | ✅ | `ReminderController.swift`（"2"） |
| macOS 窗口最小化 / 隐藏时不挂起数据库 | 🔧 | 原来任何窗口进 `.background` 都挂起整个进程的数据库（菜单栏、同步、通知按钮都写不进）。现在挂起只在 iOS 上做 |
| 重复：RRULE 子集、按到期或完成日期、截止日期或次数 | ✅ | `OpenTodoDomain/Recurrence.swift`；`RecurrenceTests`（26/26） |
| 完成后挪到下一次（晚于原日期也晚于今天），留已完成副本（UUIDv5） | ✅ | `TaskRepo.swift`；`OpenTodoData/Ids.swift` |
| 子任务清空勾选、副本带子任务副本 | ✅ | `TaskRepo.swift` |
| 最后一次完成时正常关闭 | ✅ | `TaskRepo.swift` |
| 跳过此次只挪日期，跳过最后一次是 wontDo | ✅ | `TaskRepo.skipOccurrence`；`TaskMenu`、`AppCommands` |
| 撤销重复任务的完成 | ✅ | `TaskRepo.undoRepeatCompletion`；`AppModel+Actions.swift` |
| 清除日期连带清掉提醒和重复 | ✅ | `TaskRepo.setDue` |
| 时间段：日期对话框的“时间段”、日历拖下边缘、跨天每天显示 | ✅ | `ScheduleEditorView.swift`；`CalendarChips.swift` |
| 重复菜单：法定工作日、农历每年、农历每月 | ✅ | `Schedule/ScheduleEditor.swift` |
| 自定义重复：按农历、按法定节假日调休 | ✅ | `Schedule/SchedulePages.swift` |
| 节假日数据 2025–2027、农历表 | ✅ | `OpenTodoDomain/Holidays.swift`、`Lunar.swift`；`HolidaysTests`、`LunarTests` |
| 快速添加识别重复、法定工作日、农历、时间段；有时间的带准时提醒 | ✅ | `QuickAddParser.swift`；`AppModel+Actions.swift` |
| 设置页：系统通知状态、任务默认值、稍后提醒 | ✅ | `Settings/SettingsSections.swift`；`OpenTodoSettingsView.swift` |
| macOS 设置窗口、iPhone 设置 sheet 的内容 | ✅ | `Shell/SettingsView.swift` → `OpenTodoSettingsView` |
| iPad 全屏的设置入口 | 🔧 | 见第 1 节 |
| macOS 没有窗口开着时点通知 | ❓ | `openRequest` 等下一个窗口出现才处理，应用不会自己开窗口 |
| Swift 新加：艾宾浩斯重复（规则、日期对话框、快速添加） | ✅ | `Recurrence.swift`（`X-EBBINGHAUS`，第 1/2/4/7/15/30/90/180 天）；`EbbinghausTests`；`ScheduleEditor.swift`；`QuickAddParser.swift` |
| app_test：重复任务完成后挪下一次、撤销、提醒跟着走 | ✅ | `AppModelTests`；`ReminderTests`；`ReminderControllerTests` |
| app_test：通知按钮（稍后提醒、完成、点开） | ✅ | `ReminderTests`；`AppModelTests`（`handle(.task)`） |
| app_test：日期对话框设提醒和重复 | ✅ | `ScheduleEditorTests` |
| app_test：法定工作日 / 农历重复 | ✅ | `ScheduleEditorTests` |
| 单测文件对应：recurrence 26、reminders 6、reminder_scheduler 2、reminder_actions 8、repo 21、sync_codec 4、sync_integration 9、migration 1、task_defaults 2、holidays 3、lunar 5、quick_add_parser 34、dates 9 | ✅ | `OpenTodoKit/Tests/` 里全部有对应，没有缺的、没有禁用的 |

## 6. 效率模块、系统集成、应用图标

| 功能点 | 结论 | Swift 位置 / 说明 |
|---|---|---|
| 习惯：频率三种，读不懂的当每天 | ✅ | `OpenTodoDomain/Efficiency/Habits.swift` `HabitFrequency`；`HabitsTests` |
| 习惯：打卡 ID = v5(`habitId/日期`)；取消打卡写删除标记，再打卡同一 ID | ✅ | `Habits.swift`；`OpenTodoData/EfficiencyRepo.swift` `undoCheckin` |
| 习惯：计数按目标算 status，“完成”只看 status | ✅ | `Habits.swift` |
| 习惯：该不该打卡、连续天数（按天 / 按周的各种情况）、月完成率、今天的列表 | ✅ | `Habits.swift` `isDue` / `streak` / `monthCompletionRate` / `todayHabits`；`HabitsTests` |
| 专注：有效 5 分钟、番茄走满总记录、放弃记 completed=false、番茄数只数完成的 | ✅ | `Efficiency/Focus.swift`；`FocusTests` |
| 专注：被杀后补算（含自动开始）、长休息、休息不能暂停 | ✅ | `Focus.swift` `tick` / `nextBreak` / `pause` |
| 专注：设置默认值（25/5/15/4/关），存 `focus.settings` | ✅ | `Focus.swift`；`OpenTodoData/Settings.swift` |
| 专注：在设置里改时长不改正在跑的番茄 | 🔧 | 原来 `FocusRootView` 不管计时器在不在跑都换上新设置。现在只在空闲时换 |
| 专注：统计按开始那天、柱状图含空格、分布、时间轴截断 | ✅ | `Focus.swift`；`FocusTests` |
| 倒数日：下一次（公历月底、农历普通月、没有三十取廿九、每月含闰月） | ✅ | `Efficiency/Countdowns.swift`；`CountdownsTests` |
| 倒数日：显示格式、岁数、列表排序、显示在今天 | ✅ | `Countdowns.swift`；`CountdownsTests` |
| 四象限：默认按优先级、补齐和丢弃、`matrix.prefs` | ✅ | `Efficiency/Matrix.swift`；`MatrixTests` |
| 四象限：分象限、排序、拖进象限改什么 | ✅ | `Matrix.swift` `matrixCells` / `movedIntoQuadrant`；`MatrixTests` |
| AppModule 四个 case，⌘3–⌘6 | ✅ | `Model/AppModule.swift`；`AppCommands.swift` |
| Mac 侧栏里的四行和行尾的近况 | ✅ | `Tasks/ViewsList.swift` `ModuleRow`；`EfficiencyScreen.swift` `moduleBadge` / `efficiencySummary`。原来效率模块有自己的侧栏，把四个模块又列了一遍，2026-11-27 并进窗口的侧栏 |
| iPhone 合成一个“效率”标签、标题菜单切换 | ✅ | `EfficiencyScreen.swift`；`RootView.swift` |
| 写操作调 EfficiencyRepo；删倒数日、删专注记录带撤销 | ✅ | `Efficiency/App/EfficiencyModel.swift` |
| 专注计时器存 LocalSettings、启动时读回补算、别的模块在前台时每 5 秒看钟 | ✅ | `EfficiencyModel.swift` `start` / `timerChanged` / `runTicker` |
| 同上，多个窗口时 | 🔧 | 原来每个窗口一份。验收期间 5d29a73 补上（`OpenTodoData/FocusTimerStore.swift`，挂在 `AppServices` 上，整个应用一份；`EfficiencyIntegrationTests`） |
| 专注结束的通知（固定 ID） | ✅ | `Efficiency/App/FocusEndNotifier.swift` |
| 任务右键 / 详情“更多”里的“开始专注” | ✅ | `TaskMenu.swift`；`EfficiencyScreen.swift`；`EfficiencyModel.swift` |
| 同上：开始的是番茄还是正计时 | ❓ | 文档写“开始一个番茄”，代码按计时器当前的模式（可能是正计时），注释说是有意的。请定一下 |
| “今天”顶上的倒数日（`TodayCountdownsRow`），点了打开详情 | ✅ | `TaskListView.swift`；`EfficiencyScreen.swift` |
| 四象限：勾选、点开、拖动、快速添加、规则编辑（FilterEditor）、存本机 | ✅ | `EfficiencyScreen.swift`（`setDone` / `revealTask` / `repo.updateTask` / `quickAdd` / `FilterEditor` / `setMatrixPrefs`） |
| 习惯和倒数日的提醒和任务提醒一起排进系统；通知点开对应模块 | ✅ | `ReminderActions.swift` `ReminderSources`；`Efficiency/EfficiencyReminders.swift`；`AppModel.handle` |
| 演示数据 | ✅ | `Model/AppLaunch.swift`；`Efficiency/EfficiencyDebug.swift` |
| App Group、entitlement、`OT_APP_GROUP` / `OT_URL_SCHEME`、沙盒 | ✅ | `apple/project.yml`；`apple/App/*.entitlements`；`apple/Extensions/` |
| 数据库搬进 App Group | ✅ | `OpenTodoData/Database.swift` `moveIntoGroup` |
| 扩展先于应用写库 | 🔧 | 原来分享扩展、快捷指令在应用没打开过时会在组里新建一个空库，应用之后就不再把旧库（Flutter 版的）复制进来。现在扩展不建库，提示先打开一次 OpenTodo；`Writing.anExtensionDoesNotMakeTheDatabaseBeforeTheApp` |
| 小组件：今天（小 / 中 / 大）、勾选、链接 | ✅ | `apple/Widgets/TodayTasksWidget.swift`（`CompleteTaskIntent`） |
| 小组件：快速添加、倒数日（可选哪个）、习惯 | ✅ | `Widgets/OpenTodoWidgets.swift`、`EfficiencyWidgets.swift`；`Intents/TaskIntents.swift` `SelectCountdownIntent` |
| WidgetStore 只读；SharedWriter 经 TaskRepo 写 | ✅ | `OpenTodoSystem/WidgetContent.swift`；`OpenTodoSystem/SharedWriter.swift` |
| ChangeSignal：应用窗口收到后重读 | ✅ | `SharedWriter.swift`；`OpenTodoUI/System/SystemIntegration.swift` |
| ChangeSignal：菜单栏小窗、没有窗口时 | 🔧 | 原来只有当前窗口重读。验收期间 f58cdb9 挪到进程级（`System/SystemSync.swift`，各窗口和菜单栏 / 快速添加面板都重读，窗口全关了小组件和 Spotlight 照常；`SystemSyncTests`） |
| iOS 进后台放开文件 | ✅ | `RootView.swift` → `AppServices.appDidEnterBackground`（现在只在 iOS） |
| 数据变了 1 秒后刷新小组件和 Spotlight；`widgetRefreshTimes` | ✅ | `SystemIntegration.swift`；`OpenTodoSystem/SpotlightContent.swift`、`WidgetContent.swift` |
| AppLink 七种链接都能打开 | ✅ | `OpenTodoSystem/AppLink.swift`；`SystemIntegration.swift` |
| App Intents：添加任务（只给时间就是今天）、打开清单、完成任务；App Shortcuts 短语 | ✅ | `apple/Intents/TaskIntents.swift`；`SharedWriter.intentDue`；`apple/App/AppShortcuts.swift` |
| macOS 菜单栏小窗：今天的任务勾选 / 点开、快速添加到今天、今天的专注 | ✅ | `OpenTodoUI/System/MenuBar.swift` |
| 全局快捷键 ⌃⇧A（Carbon、非激活 NSPanel、回车加到收集箱、写了日期按日期、Esc 和点别处取消、被占用提示） | ✅ | `System/GlobalHotKey.swift`、`QuickAddPanel.swift`；`OpenTodoSystem/HotKey.swift` |
| 设置 → 快速添加：开关和录制（UserDefaults） | ✅ | `System/IntegrationSettings.swift` |
| 带 `-OTDatabasePath` 时不注册快捷键 | ✅ | `System/SystemServices.swift` |
| 分享扩展：文字 / 链接存成任务 | ✅ | `apple/ShareExtension/ShareViewController.swift`；`OpenTodoSystem/SharedContent.swift` |
| 应用图标：脚本、iOS 三张 1024（浅色 / 深色 / 着色）、macOS 16–1024，`Contents.json` 引用齐全 | ✅ | `apple/scripts/make_icon.swift`；`App/Assets.xcassets/AppIcon.appiconset`（10 张 PNG、13 条引用都在） |

小出入（文档没要求，不改）：倒数日卡片的显示格式只存在窗口内存里；iPhone“效率”标签上次用的模块不持久；分享扩展存完不刷新小组件；点专注结束的通知只打开应用、不切到专注模块。

## Flutter 版本身

对照时没发现要照搬的 Flutter 错误。

## 验证

在合进最新 swift-native 以后跑的：`swift build && swift test` 全过（287 + 30 + 354 + 136 = 807 个测试），`scripts/build.sh macos` 和 `build.sh ios` 都编过。macOS 调试版用 `-OTOpen list:work`、`calendar:month` 打开能一直跑，`timeline:list:work` 和 `timeline:smart:today` 几秒后崩溃（第 0 件）。没有开 iOS 模拟器（另有人做 iOS 验收）。

2026-11-26 收尾（swift-native 上）：`swift build && swift test` 全过（292 + 30 + 355 + 138 = 815 个测试），`build.sh macos`（签名）和 `build.sh ios` 都编过；时间线路由在两种窗口宽度下各跑 80 秒都活着（第 0 件）；iOS 界面测试 `SmokeUITests` 3 个、`TimelineDragUITests` 3 个在模拟器上都过。

