# WallpaperSwitcher

## 项目简介
`WallpaperSwitcher` 是一个面向个人自用的 macOS 壁纸切换工具，当前目标是基于“系统里已经下载到本机的壁纸资源”完成最小闭环：扫描、展示、点击切换、随机切换和自动轮换。

当前项目已经支持：

- 扫描 macOS 本地已存在的系统壁纸资源
- 按 `Dynamic Wallpapers` / `Pictures` 分区展示
- 点击任意壁纸立即设置为当前桌面
- `Shuffle Scope` 随机范围切换：`All` / `Dynamic` / `Pictures`
- `Auto Shuffle` 自动轮换
- interval 快捷预设 + 自定义 `day / hour / minute`
- 大窗口网格展示、小窗口自动切换为列表展示
- 启动 loading 占位、上次扫描结果 metadata 缓存、后台低占用优化

## 当前功能列表
从用户视角看，当前已实现的功能如下：

- 启动后自动读取上次缓存的壁纸列表，并在后台刷新扫描结果
- 扫描本机常见系统壁纸目录，只保留本地真实存在的 `jpg / jpeg / png / heic`
- 过滤 `Solid Colors` 纯色壁纸
- 全局排除 `Sequoia Sunrise.heic`、`Sonoma Horizon.heic`
- 结果按 `Dynamic Wallpapers` 和 `Pictures` 分区显示
- 每项展示缩略图、文件名、分类 tag、文件路径
- 当前生效壁纸会有轻量高亮和 `Current` 标记
- `Refresh Scan` 手动强制刷新扫描
- `Shuffle Now` 立即随机切换
- `Start Auto Shuffle` / `Stop Auto Shuffle` 控制自动轮换
- `Shuffle Scope` 控制随机池范围
- 支持快捷预设：`1m / 5m / 15m / 30m / 1h / 2h / 24h`
- 支持自定义 `d / h / min` 输入，且带归一化进位
- 宽窗口下使用壁纸卡片网格，窄窗口下自动切换为列表

## 技术栈
- SwiftUI
- AppKit bridge
- ImageIO
- UserDefaults
- NSCache

当前实际使用到的系统能力包括：

- `NSWorkspace.setDesktopImageURL(_:for:options:)` 设置壁纸
- `NSScreen` + `CGDisplayIsBuiltin` 解析目标显示器
- `NSViewRepresentable` 监听窗口可见性变化
- `CGImageSourceCreateThumbnailAtIndex` 生成缩略图
- `DispatchSourceTimer` 做自动轮换调度

## 项目结构
- [AppEntry.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/AppEntry.swift)
  SwiftUI 应用入口，创建主窗口和 `AppViewModel`，触发 `initialLoad()`

- [ContentView.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/ContentView.swift)
  主界面。负责顶部操作区、状态区、分区展示、grid/list 响应式布局、加载占位和缩略图展示

- [AppViewModel.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/AppViewModel.swift)
  核心状态层。负责扫描结果分区、Shuffle Scope、interval 状态、缓存读写、启动加载状态、Auto Shuffle 触发入口

- [WallpaperScanner.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/WallpaperScanner.swift)
  壁纸扫描器。负责扫描系统目录、过滤扩展名、过滤纯色壁纸、全局排除名单、启发式分类

- [WallpaperShuffleService.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/WallpaperShuffleService.swift)
  壁纸切换服务。负责设置桌面图、随机选择、Auto Shuffle 定时器调度、当前壁纸路径和错误状态

- [BuiltInDisplayResolver.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/BuiltInDisplayResolver.swift)
  目标显示器解析器。优先内置显示器，找不到再回退到 `NSScreen.main` 或第一块屏幕

- [WallpaperItem.swift](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/WallpaperItem.swift)
  壁纸数据模型，包含 `id / fileURL / fileName / categoryGuess / isHEIC`

- [Info.plist](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher/Info.plist)
  应用信息和图标配置

## 运行方式
1. 用 Xcode 打开 [WallpaperSwitcher.xcodeproj](/Users/lcy/Code/wallpaper-switcher/WallpaperSwitcher.xcodeproj)
2. 选择 `WallpaperSwitcher` target / scheme
3. 直接 `Run`

当前最低支持系统：

- macOS 14.0+

## 当前已实现的核心交互
- `Refresh Scan`
  立即强制刷新本地壁纸扫描结果

- `Shuffle Now`
  按当前 `Shuffle Scope` 从有效随机池里立即切换一张壁纸

- `Start Auto Shuffle` / `Stop Auto Shuffle`
  开启或停止自动轮换。运行中修改 interval 会立即重启 timer，应用新间隔

- `Shuffle Scope`
  支持 `All` / `Dynamic Wallpapers` / `Pictures`

- interval 预设和自定义
  顶部支持快捷预设和 `d / h / min` 输入；超过范围时会自动进位归一化

- 响应式 grid/list
  大窗口显示网格卡片，小窗口自动切为列表行

- 点击切换
  点击任意壁纸卡片或列表项，会立即切换当前桌面壁纸

## 注意事项 / 已知限制
- 只依赖“系统本地已下载”的壁纸资源，不会拉取未下载壁纸
- 动态壁纸分类是启发式规则，不是 Apple 公开稳定接口
- 当前只把 `com.apple.mobileAssetDesktop` 下的资源视为 true dynamic
- `Sequoia Sunrise.heic`、`Sonoma Horizon.heic` 被显式全局排除，不参与展示和 shuffle
- `Solid Colors` 纯色壁纸会被路径规则过滤
- 只切换一个目标显示器，优先内置显示器
- 未做菜单栏版、登录启动、App Store / Sandbox 适配
- 未做系统级后台 agent / daemon，只是普通 macOS app
- 缩略图和 metadata 缓存已经有轻量优化，但仍有继续优化空间
