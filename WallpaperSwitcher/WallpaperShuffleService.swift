import AppKit
import Foundation

@MainActor
final class WallpaperShuffleService {
    private let displayResolver: BuiltInDisplayResolver
    private let timerQueue = DispatchQueue(label: "WallpaperSwitcher.autoShuffleTimer", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastAppliedItemID: WallpaperItem.ID?

    private(set) var currentWallpaperURL: URL?
    private(set) var lastErrorMessage: String?
    private(set) var isAutoShuffleRunning = false
    private(set) var currentInterval: TimeInterval?

    init(displayResolver: BuiltInDisplayResolver = BuiltInDisplayResolver()) {
        self.displayResolver = displayResolver
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }

    func apply(_ item: WallpaperItem) {
        guard let screen = displayResolver.resolveTargetScreen() else {
            setError("未找到可用显示器，无法设置壁纸。")
            return
        }

        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]

        do {
            try NSWorkspace.shared.setDesktopImageURL(
                item.fileURL,
                for: screen,
                options: options
            )
            currentWallpaperURL = item.fileURL
            lastAppliedItemID = item.id
            lastErrorMessage = nil
        } catch {
            setError("设置壁纸失败: \(error.localizedDescription)")
        }
    }

    func shuffle(from items: [WallpaperItem]) {
        guard !items.isEmpty else {
            setError("当前没有可用壁纸，无法随机切换。")
            return
        }

        let candidates: [WallpaperItem]
        if items.count > 1, let lastAppliedItemID {
            let filtered = items.filter { $0.id != lastAppliedItemID }
            candidates = filtered.isEmpty ? items : filtered
        } else {
            candidates = items
        }

        guard let selectedItem = candidates.randomElement() else {
            setError("随机选择壁纸失败。")
            return
        }

        apply(selectedItem)
    }

    func startAutoShuffle(interval: TimeInterval, itemsProvider: @escaping @MainActor () -> [WallpaperItem]) {
        stopAutoShuffle(clearError: false)

        currentInterval = interval
        isAutoShuffleRunning = true
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        let leewaySeconds = max(interval * 0.1, 1)

        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(leewaySeconds * 1000))
        )
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.shuffle(from: itemsProvider())
            }
        }
        timer.resume()
        self.timer = timer
    }

    func stopAutoShuffle(clearError: Bool = true) {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        isAutoShuffleRunning = false
        currentInterval = nil

        if clearError {
            lastErrorMessage = nil
        }
    }

    func refreshCurrentWallpaper() {
        guard let screen = displayResolver.resolveTargetScreen() else {
            currentWallpaperURL = nil
            setError("未找到可用显示器，无法读取当前壁纸。")
            return
        }

        if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
            currentWallpaperURL = url
            lastAppliedItemID = url.standardizedFileURL.resolvingSymlinksInPath().path
            lastErrorMessage = nil
        } else {
            currentWallpaperURL = nil
            setError("读取当前壁纸失败。")
        }
    }

    private func setError(_ message: String) {
        lastErrorMessage = message
    }
}
