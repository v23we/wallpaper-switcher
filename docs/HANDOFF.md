# HANDOFF

## 项目目标
这个项目当前解决的问题很明确：

- 扫描 macOS 本机已经存在的系统壁纸资源
- 让用户可以浏览这些壁纸
- 点击立即切换当前桌面壁纸
- 支持按范围随机切换和自动轮换

它不是一个“下载壁纸平台”，也不是完整的菜单栏常驻代理。当前定位仍然是一个可运行、可继续迭代的个人自用 macOS demo。

## 当前实现状态
按模块看，当前已经完成到以下程度：

- 扫描层
  已实现常见系统壁纸目录扫描、扩展名过滤、纯色壁纸过滤、全局排除名单、启发式分类、扫描路径回显和 warning 收集。

- 数据模型层
  已有稳定的 `WallpaperItem`，字段满足展示、切换、分类和缓存需求。

- 显示器解析层
  已实现“优先内置显示器，否则 `NSScreen.main`，再否则第一块屏幕”的目标屏幕选择。

- 壁纸切换层
  已使用 `NSWorkspace.setDesktopImageURL(_:for:options:)` 真正切换壁纸；随机切换会避免连续重复同一张。

- 轮换层
  已支持 `Shuffle Scope`、手动 `Shuffle Now`、自动轮换 timer、运行中 interval 重应用。

- interval 层
  已支持预设 + 自定义 `day / hour / minute`；输入会归一化进位，最大钳制到 `99d 23h 59min`。

- UI 层
  已有顶部操作区、状态区、分区展示、响应式 grid/list、当前壁纸高亮、启动 loading skeleton 和 empty state。

- 缓存 / 启动体验
  已支持 metadata 缓存，启动先展示缓存结果，再后台刷新扫描。

- 后台低占用
  已做轻量优化：Auto Shuffle 仅在开启时保留 timer；窗口不可见时暂停新的缩略图生成并清理缩略图缓存。

## 核心设计决策
### 为什么不做系统未下载壁纸拉取
当前项目目标是“本机已下载资源扫描 + 切换 + shuffle”的最小闭环。系统未下载资源涉及 Apple 私有目录、下载流程、权限和稳定性，不适合在这个 demo 阶段扩展。

### 为什么动态壁纸分类用启发式
Apple 没有提供稳定的公开接口告诉应用“哪些文件是系统动态壁纸、哪些只是普通 HEIC”。当前实现只能根据已知目录结构做启发式判断。

### 为什么过滤纯色壁纸
用户目标是壁纸浏览和随机切换，而不是把 `Black / Cyan / Dusty Rose` 这类纯色项混进候选池。当前用路径过滤是最小且稳定的做法。

### 为什么有全局排除名单
`Sequoia Sunrise.heic` 和 `Sonoma Horizon.heic` 会误导成“像动态壁纸”，但对这个项目的定义来说不应该出现在任何分区和 shuffle 池里。与其重新分类，不如在 scanner 阶段直接全局移除。

### 为什么大窗口用 grid、小窗口切 list
大窗口更适合当“壁纸浏览器”，小窗口更适合当“资源列表”。这比在小宽度下硬塞卡片可读性更好，也更符合当前项目的轻量原生风格。

### 为什么 interval 用 d/h/min 模型
固定档位不够灵活，小时和分钟也不够覆盖“按天轮换”的实际使用场景。`day / hour / minute` 是目前够用且简单的时间模型。

### 为什么后台优化只做轻量调度和缩略图降载
当前项目仍是普通 macOS app，不是 daemon。最划算的优化点是减少 timer 唤醒、避免后台继续生成缩略图、限制内存缓存，而不是引入更重的后台架构。

## 核心文件职责详解
### [AppEntry.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/AppEntry.swift)
负责什么：

- SwiftUI 入口
- 创建全局 `AppViewModel`
- 设置窗口最小尺寸
- 启动时调用 `initialLoad()`

主要状态在哪里：

- 没有业务状态，只有入口和窗口配置

哪些逻辑不能乱改：

- `.task { viewModel.initialLoad() }`
  它和启动缓存、后台刷新策略直接相关

哪些地方最容易出 bug：

- 如果改成重复创建 `AppViewModel`，会把 Auto Shuffle 状态和缓存恢复链路打散

### [ContentView.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/ContentView.swift)
负责什么：

- 主界面全部展示
- 顶部操作区
- 状态区
- loading / empty / normal 三态
- 分区展示
- grid/list 响应式切换
- 缩略图展示
- 窗口不可见时的 UI 降载

主要状态在哪里：

- UI 绑定状态大多来自 `AppViewModel`
- 缩略图缓存和窗口可见性监听写在这个文件里

哪些逻辑不能乱改：

- `WallpaperSectionLayoutMode.forWidth`
- `WindowVisibilityObserver`
- `ThumbnailProvider`
- loading / empty / normal 三态分支

哪些地方最容易出 bug：

- grid/list 两套布局的视觉和交互要保持一致
- 隐藏窗口时如果把缩略图逻辑改重，容易重新引入后台占用

### [AppViewModel.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/AppViewModel.swift)
负责什么：

- 整个 app 的核心状态层
- 扫描结果存储和分区
- Shuffle Scope
- interval 状态与归一化
- metadata 缓存读写
- 启动加载状态
- Auto Shuffle 触发入口和 timer 重应用

主要状态在哪里：

- `wallpapers / dynamicItems / pictureItems`
- `selectedShuffleScope`
- `intervalDays / intervalHours / intervalMinutes`
- `isInitialLoading / hasLoadedOnce / cachedItemsLoaded`

哪些逻辑不能乱改：

- `currentShufflePool`
- `updateInterval(...)`
- `normalizeInterval(...)`
- `initialLoad()`
- `refreshScan(...)`
- `rebuildSections(...)`

哪些地方最容易出 bug：

- interval 输入、归一化和 timer 重应用之间的联动
- 启动缓存、首次 loading、后台刷新三者的状态切换

### [WallpaperScanner.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/WallpaperScanner.swift)
负责什么：

- 扫描本机壁纸目录
- 过滤不支持扩展名
- 过滤纯色壁纸
- 过滤全局排除名单
- 分类为 `dynamic / picture / unknown`

主要状态在哪里：

- 无持久状态，扫描时临时构造 `ScanResult`

哪些逻辑不能乱改：

- `solidColorsDirectoryPrefix`
- `globallyExcludedWallpaperFilenames`
- `category(for:)`

哪些地方最容易出 bug：

- 系统目录是启发式，未来 macOS 版本可能变化
- 误把缩略图资源、辅助资源或包装资源当成真正壁纸文件

### [WallpaperShuffleService.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/WallpaperShuffleService.swift)
负责什么：

- 设置桌面图
- 立即 shuffle
- Auto Shuffle 调度
- 当前壁纸 URL 和错误状态

主要状态在哪里：

- `currentWallpaperURL`
- `lastErrorMessage`
- `isAutoShuffleRunning`
- `currentInterval`
- `lastAppliedItemID`

哪些逻辑不能乱改：

- `apply(_:)`
- `shuffle(from:)`
- `startAutoShuffle(...)`
- `stopAutoShuffle(...)`

哪些地方最容易出 bug：

- timer 生命周期
- 随机池为空时的状态提示
- 避免连续重复同一张的逻辑

### [BuiltInDisplayResolver.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/BuiltInDisplayResolver.swift)
负责什么：

- 选出“当前应该切哪块屏幕”

主要状态在哪里：

- 无状态

哪些逻辑不能乱改：

- “优先内置显示器，否则主屏，否则第一块屏”这条回退链

哪些地方最容易出 bug：

- `NSScreenNumber` 提取失败时的回退

### [WallpaperItem.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/WallpaperItem.swift)
负责什么：

- 壁纸条目模型
- 统一文件路径标准化

主要状态在哪里：

- `id / fileURL / fileName / categoryGuess / isHEIC`

哪些逻辑不能乱改：

- `id` 现在就是标准化后的真实路径，很多去重和当前壁纸判断都依赖它

哪些地方最容易出 bug：

- 如果以后改 `id` 语义，scanner 去重、当前壁纸高亮和随机去重都可能受影响

## 当前关键逻辑说明
### 壁纸扫描逻辑
扫描根目录当前是：

- `/System/Library/Desktop Pictures`
- `/System/Library/Desktop Pictures/.wallpapers`
- `~/Library/Application Support/com.apple.mobileAssetDesktop`

辅助调试路径：

- `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`

过滤规则：

- 只保留 `jpg / jpeg / png / heic`
- 必须是本地真实存在的普通文件
- 跳过 `.thumbnails`
- 跳过文件名里明显是 `thumbnail` 的资源

### dynamic / picture 分类逻辑
当前规则在 `WallpaperScanner.category(for:)`：

- `com.apple.mobileAssetDesktop` 下的资源视为 `dynamic`
- 路径包含 `/Desktop Pictures` 的归为 `picture`
- 其余归为 `unknown`

`AppViewModel.rebuildSections(...)` 里又做了一层分区收口：

- `dynamicItems = categoryGuess == .dynamic`
- `pictureItems = categoryGuess == .picture || .unknown`

也就是说，`unknown` 现在会进 `Pictures` 分区。

### 全局排除名单
当前 scanner 会直接排除：

- `Sequoia Sunrise.heic`
- `Sonoma Horizon.heic`

这不是“重新分类”，而是“扫描阶段直接不进入最终结果”。

### Shuffle Scope 的随机池逻辑
当前随机池统一由 `AppViewModel.currentShufflePool` 提供：

- `All` -> `wallpapers`
- `Dynamic` -> `dynamicItems`
- `Pictures` -> `pictureItems`

`Shuffle Now` 和 `Auto Shuffle` 都吃同一个池，避免三套逻辑分叉。

### Auto Shuffle timer 逻辑
当前使用 `DispatchSourceTimer`：

- 只有开启 Auto Shuffle 时才创建
- Stop 时立刻 `cancel()`
- 使用 `utility` QoS
- 带约 10% 的 `leeway`

这是当前项目的轻量节能方案，不是高频轮询。

### interval 归一化 / 进位逻辑
当前 interval 统一在 `AppViewModel.normalizeInterval(...)` 里处理：

- 输入模型：`days + hours + minutes`
- 先转总分钟
- 再拆回归一化后的 `d / h / min`
- `hours` 最终在 `0...23`
- `minutes` 最终在 `0...59`
- 全部为 0 时自动修正为 `0d 0h 1min`
- 最大钳制为 `99d 23h 59min`

### grid/list 响应式切换逻辑
当前阈值在 `WallpaperSectionLayoutMode.forWidth(_:)`：

- 宽度 `< 900` -> `list`
- 否则 -> `grid`

这是自动切换，没有手动按钮。

### 当前壁纸高亮逻辑
当前判断方式很直接：

- `item.fileURL.path == currentWallpaperPath`

网格和列表都基于同一判断显示 `Current` 样式。

### 启动 loading / 缓存逻辑
启动链路当前是：

1. `initialLoad()` 读取当前桌面壁纸
2. 尝试从 `UserDefaults` 读取上次缓存的壁纸 metadata
3. 如果有缓存，先展示缓存结果
4. 再后台低优先级刷新真实扫描结果

UI 三态：

- 首次加载中：skeleton
- 已加载但无结果：empty state
- 有数据：正常展示

### 后台低占用优化逻辑
当前已做：

- Auto Shuffle 仅在运行时保留 timer
- timer 有 `leeway`
- 窗口隐藏、最小化、关闭、应用 hide 时暂停新的缩略图生成
- 缩略图缓存使用 `NSCache` 限制数量和总成本
- 窗口不可见时清理缓存
- 缩略图统一走 `CGImageSourceCreateThumbnailAtIndex`

当前没有做：

- 更重的后台 agent 进程
- 多级缩略图磁盘缓存
- Instruments 驱动的深度性能调优

## 当前缓存 / 存储项
当前项目使用 `UserDefaults` 存这些内容：

- `WallpaperSwitcher.cachedWallpaperItems`
  上次扫描成功后的壁纸 metadata 列表，只存路径和分类，不存缩略图二进制

- `WallpaperSwitcher.intervalDays`
- `WallpaperSwitcher.intervalHours`
- `WallpaperSwitcher.intervalMinutes`

当前内存缓存：

- `ContentView.ThumbnailProvider` 里的 `NSCache<NSURL, NSImage>`

不确定项：

- 当前没有独立磁盘缩略图缓存

## 现在还没做的事情
按当前代码真实状态，后续待办可以这样看：

### 可做但未做
- 更精细的动态壁纸识别，而不是继续依赖路径启发式
- 多显示器策略扩展，例如手动指定目标屏幕
- 菜单栏版 UI
- 登录启动
- 更细的缩略图磁盘缓存或预热策略
- 错误展示和调试信息进一步结构化

### 不建议现在做
- 一上来重构成复杂架构或引入第三方依赖
- 过早做“云壁纸下载”或在线资源同步
- 把 demo 直接拉向 App Store / Sandbox 适配

### 高风险项
- 修改 scanner 路径与分类规则时，容易误伤现有分区和 shuffle 结果
- 修改 `WallpaperItem.id` 语义时，容易破坏去重和当前壁纸判断
- 改 timer 或 interval 逻辑时，容易影响 Auto Shuffle 行为
- 改缩略图路径时，容易重新引入后台高占用或大图解码

## 后续接手建议
### 先看哪些文件
建议先看这几个文件，能最快理解项目：

1. [AppViewModel.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/AppViewModel.swift)
2. [ContentView.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/ContentView.swift)
3. [WallpaperScanner.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/WallpaperScanner.swift)
4. [WallpaperShuffleService.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/WallpaperShuffleService.swift)

### 先跑哪些功能
接手后建议优先手动验证：

1. 启动后是否先显示缓存或 loading，再平滑切到真实结果
2. 点击壁纸是否立即切换
3. `Shuffle Scope` 三个范围是否工作正常
4. `Start Auto Shuffle` 后修改 interval 是否立即生效
5. 大窗口 grid、小窗口 list 是否自动切换

### 改 UI 主要看哪里
- [ContentView.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/ContentView.swift)

### 改扫描和分类逻辑主要看哪里
- [WallpaperScanner.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/WallpaperScanner.swift)
- [AppViewModel.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/AppViewModel.swift)

### 改后台占用主要看哪里
- [WallpaperShuffleService.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/WallpaperShuffleService.swift)
- [ContentView.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/ContentView.swift)

## 已知风险
- 系统壁纸路径和目录结构可能随 macOS 版本变化
- dynamic 分类不是 Apple 官方公开接口，当前规则是启发式
- 纯色过滤和全局排除名单都是人工规则，需要维护
- metadata 缓存和缩略图缓存仍可继续优化
- 当前不是菜单栏 agent 形态，关闭窗口后的常驻体验仍是普通 app 级别
- 若后续要做多显示器、下载壁纸或后台代理，会触及更大范围的架构选择

## 交接结论
这个项目现在已经不是空 demo，而是一个可以运行、可以继续小步迭代的 macOS 壁纸切换工具。核心链路已经完整：扫描、展示、点击切换、按范围随机、自动轮换、interval 配置、响应式展示、启动缓存和轻量后台优化都在。

后续接手时，最应该先做的是理解 `AppViewModel`、`ContentView`、`WallpaperScanner` 和 `WallpaperShuffleService` 之间的边界，再决定改 UI、改分类还是改后台策略。

不建议接手后第一步就重构架构、引入新库或扩功能面。这个项目当前最稳的推进方式仍然是：围绕既有结构做小改动、每次只改一个明确目标、每次都做构建和手工验证。
