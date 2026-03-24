# CHANGELOG

本文档不是 git 提交日志，而是按“已完成功能演进”整理出的当前版本能力脉络，方便后续 IDE / agent 快速理解项目是怎么长成现在这个状态的。

## 1. 基础最小闭环
- 创建了普通 macOS app 形态的 `WallpaperSwitcher`
- 使用 SwiftUI 作为 UI 入口
- 使用 AppKit / `NSWorkspace` 设置桌面壁纸
- 建立基础文件结构：
  - `AppEntry`
  - `ContentView`
  - `AppViewModel`
  - `WallpaperScanner`
  - `WallpaperShuffleService`
  - `BuiltInDisplayResolver`
  - `WallpaperItem`

## 2. 壁纸扫描与切换
- 扫描本机常见系统壁纸目录
- 只保留本地真实存在的 `jpg / jpeg / png / heic`
- 点击某张壁纸即可立即设置为当前桌面
- 优先切换内置显示器，找不到则回退到主屏或第一块屏

## 3. 分区与分类收口
- 扫描结果不再混在一个列表里
- 按 `Dynamic Wallpapers` 和 `Pictures` 分区展示
- `dynamicItems` 和 `pictureItems` 在 `AppViewModel` 中统一生成
- `unknown` 分类暂时归到 `Pictures`

## 4. 过滤规则补齐
- 增加 `Solid Colors` 纯色壁纸路径过滤
- 增加全局排除名单：
  - `Sequoia Sunrise.heic`
  - `Sonoma Horizon.heic`
- 明确当前动态壁纸判断是“真动态壁纸”的启发式收紧规则

## 5. Shuffle Scope 与自动轮换
- 支持 `Shuffle Scope`
  - `All`
  - `Dynamic`
  - `Pictures`
- `Shuffle Now` 和 `Auto Shuffle` 共用同一个 `currentShufflePool`
- 随机切换时避免连续重复同一张

## 6. interval 能力演进
- 最早是固定档位
- 后续改成自定义 `hours + minutes`
- 再升级成 `days + hours + minutes`
- 现在支持：
  - 预设按钮：`1m / 5m / 15m / 30m / 1h / 2h / 24h`
  - 自定义 `d / h / min`
  - 自动归一化进位
  - 运行中修改后自动重启 timer

## 7. UI 形态演进
- 从长列表逐步演进成更像“壁纸浏览器”的卡片网格
- 加入当前壁纸高亮态和 `Current` 标记
- 保留小窗口可读性，加入响应式 grid/list 切换
- 宽窗口显示卡片网格
- 窄窗口自动切成紧凑列表

## 8. 启动体验优化
- 增加首次 loading state
- 区分：
  - 首次加载中
  - 加载完成但无结果
  - 有数据正常展示
- 加入 metadata 缓存：
  - 启动先展示缓存结果
  - 再后台刷新真实扫描结果

## 9. 缩略图与后台低占用优化
- 缩略图统一使用 `CGImageSourceCreateThumbnailAtIndex`
- 避免为预览解码原始大图
- 使用 `NSCache` 做内存缓存，并加上大小限制
- Auto Shuffle timer 改成更节能的 `DispatchSourceTimer`
- timer 仅在运行时存在，Stop 后立刻取消
- 窗口隐藏 / 最小化 / 关闭后暂停新的缩略图生成并清理缓存

## 10. 当前项目状态
截至当前代码状态，项目已经具备：

- 本地系统壁纸扫描
- 分区展示
- 点击切换
- Shuffle Scope
- Auto Shuffle
- interval 预设 + 自定义 `d / h / min`
- 启动缓存与 loading
- 响应式 grid/list
- 轻量后台优化

仍未进入的阶段包括：

- 系统未下载壁纸拉取
- 菜单栏版
- 登录启动
- App Store / Sandbox 适配
- 后台 agent / daemon 化
