import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    enum ShuffleInterval: String, CaseIterable, Identifiable {
        case oneMinute = "1 min"
        case fiveMinutes = "5 min"
        case fifteenMinutes = "15 min"

        var id: String { rawValue }

        var timeInterval: TimeInterval {
            switch self {
            case .oneMinute:
                return 60
            case .fiveMinutes:
                return 300
            case .fifteenMinutes:
                return 900
            }
        }
    }

    enum ShuffleScope: String, CaseIterable, Identifiable {
        case all = "All"
        case dynamic = "Dynamic"
        case pictures = "Pictures"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all:
                return "All"
            case .dynamic:
                return "Dynamic Wallpapers"
            case .pictures:
                return "Pictures"
            }
        }
    }

    @Published private(set) var wallpapers: [WallpaperItem] = []
    @Published private(set) var dynamicItems: [WallpaperItem] = []
    @Published private(set) var pictureItems: [WallpaperItem] = []
    @Published private(set) var attemptedPaths: [String] = []
    @Published private(set) var wallpaperCount = 0
    @Published private(set) var currentWallpaperPath = "未读取"
    @Published private(set) var lastErrorMessage = "无"
    @Published private(set) var autoShuffleStatusText = "未启动"
    @Published var selectedInterval: ShuffleInterval = .fiveMinutes
    @Published var selectedShuffleScope: ShuffleScope = .all

    private let scanner: WallpaperScanner
    private let shuffleService: WallpaperShuffleService
    private var latestScanMessage: String?
    private var localStatusMessage: String?

    init(
        scanner: WallpaperScanner = WallpaperScanner(),
        shuffleService: WallpaperShuffleService? = nil
    ) {
        self.scanner = scanner
        self.shuffleService = shuffleService ?? WallpaperShuffleService()
    }

    func initialLoad() {
        refreshScan()
        shuffleService.refreshCurrentWallpaper()
        syncState()
    }

    func refreshScan() {
        let result = scanner.scan()
        wallpapers = result.items
        rebuildSections(from: result.items)
        attemptedPaths = result.attemptedPaths
        wallpaperCount = result.items.count

        if result.items.isEmpty {
            latestScanMessage = result.warnings.isEmpty ? "未扫描到壁纸资源" : result.warnings.joined(separator: "\n")
        } else {
            latestScanMessage = result.warnings.isEmpty ? nil : result.warnings.joined(separator: "\n")
        }

        if shuffleService.isAutoShuffleRunning {
            shuffleService.startAutoShuffle(interval: selectedInterval.timeInterval) { [weak self] in
                self?.currentShufflePool ?? []
            }
        }

        syncState()
    }

    func shuffleNow() {
        let pool = currentShufflePool
        guard !pool.isEmpty else {
            localStatusMessage = "当前分区无可用壁纸"
            syncState()
            return
        }

        localStatusMessage = nil
        shuffleService.shuffle(from: pool)
        syncState()
    }

    func startAutoShuffle() {
        let pool = currentShufflePool
        guard !pool.isEmpty else {
            localStatusMessage = "当前分区无可用壁纸"
            syncState()
            return
        }

        localStatusMessage = nil
        shuffleService.startAutoShuffle(interval: selectedInterval.timeInterval) { [weak self] in
            self?.currentShufflePool ?? []
        }
        syncState()
    }

    func stopAutoShuffle() {
        shuffleService.stopAutoShuffle()
        syncState()
    }

    func applyWallpaper(_ item: WallpaperItem) {
        shuffleService.apply(item)
        syncState()
    }

    var isAutoShuffleRunning: Bool {
        shuffleService.isAutoShuffleRunning
    }

    var currentShuffleScopeText: String {
        selectedShuffleScope.displayName
    }

    var currentShufflePool: [WallpaperItem] {
        switch selectedShuffleScope {
        case .all:
            return wallpapers
        case .dynamic:
            return dynamicItems
        case .pictures:
            return pictureItems
        }
    }

    private func syncState() {
        wallpaperCount = wallpapers.count
        currentWallpaperPath = shuffleService.currentWallpaperURL?.path ?? "未读取"
        if let serviceError = shuffleService.lastErrorMessage {
            lastErrorMessage = serviceError
        } else if let localStatusMessage {
            lastErrorMessage = localStatusMessage
        } else if let latestScanMessage {
            lastErrorMessage = latestScanMessage
        } else {
            lastErrorMessage = "无"
        }

        if shuffleService.isAutoShuffleRunning, let interval = shuffleService.currentInterval {
            let minutes = Int(interval / 60)
            autoShuffleStatusText = "运行中（每 \(minutes) 分钟）"
        } else {
            autoShuffleStatusText = "未启动"
        }
    }

    private func rebuildSections(from items: [WallpaperItem]) {
        dynamicItems = items
            .filter { $0.categoryGuess == .dynamic }
            .sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }

        pictureItems = items
            .filter { $0.categoryGuess == .picture || $0.categoryGuess == .unknown }
            .sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
    }
}
