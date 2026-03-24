import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    struct IntervalPreset: Identifiable, Hashable {
        let label: String
        let hours: Int
        let minutes: Int

        var id: String { label }
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
    @Published var selectedShuffleScope: ShuffleScope = .all
    @Published var intervalHours: Int {
        didSet {
            handleIntervalComponentChange()
        }
    }
    @Published var intervalMinutes: Int {
        didSet {
            handleIntervalComponentChange()
        }
    }

    private let scanner: WallpaperScanner
    private let shuffleService: WallpaperShuffleService
    private var latestScanMessage: String?
    private var localStatusMessage: String?
    private let userDefaults: UserDefaults
    private var isAdjustingIntervalInternally = false

    static let intervalPresets: [IntervalPreset] = [
        IntervalPreset(label: "1m", hours: 0, minutes: 1),
        IntervalPreset(label: "5m", hours: 0, minutes: 5),
        IntervalPreset(label: "15m", hours: 0, minutes: 15),
        IntervalPreset(label: "30m", hours: 0, minutes: 30),
        IntervalPreset(label: "1h", hours: 1, minutes: 0),
        IntervalPreset(label: "2h", hours: 2, minutes: 0)
    ]

    private enum UserDefaultsKey {
        static let intervalHours = "WallpaperSwitcher.intervalHours"
        static let intervalMinutes = "WallpaperSwitcher.intervalMinutes"
    }

    init(
        scanner: WallpaperScanner = WallpaperScanner(),
        shuffleService: WallpaperShuffleService? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.scanner = scanner
        self.shuffleService = shuffleService ?? WallpaperShuffleService()
        self.userDefaults = userDefaults

        let storedHoursObject = userDefaults.object(forKey: UserDefaultsKey.intervalHours)
        let storedMinutesObject = userDefaults.object(forKey: UserDefaultsKey.intervalMinutes)
        let storedHours = storedHoursObject == nil ? 0 : userDefaults.integer(forKey: UserDefaultsKey.intervalHours)
        let storedMinutes = storedMinutesObject == nil ? 5 : userDefaults.integer(forKey: UserDefaultsKey.intervalMinutes)
        let normalized = AppViewModel.normalizedInterval(hours: storedHours, minutes: storedMinutes)
        self.intervalHours = normalized.hours
        self.intervalMinutes = normalized.minutes
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
            shuffleService.startAutoShuffle(interval: effectiveIntervalSeconds) { [weak self] in
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
        shuffleService.startAutoShuffle(interval: effectiveIntervalSeconds) { [weak self] in
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

    var effectiveIntervalSeconds: TimeInterval {
        TimeInterval((intervalHours * 3600) + (intervalMinutes * 60))
    }

    var intervalPresetOptions: [IntervalPreset] {
        Self.intervalPresets
    }

    var activeIntervalPreset: IntervalPreset? {
        Self.intervalPresets.first { preset in
            preset.hours == intervalHours && preset.minutes == intervalMinutes
        }
    }

    func applyIntervalPreset(_ preset: IntervalPreset) {
        updateInterval(hours: preset.hours, minutes: preset.minutes)
    }

    func updateInterval(hours: Int? = nil, minutes: Int? = nil) {
        let nextHours = hours ?? intervalHours
        let nextMinutes = minutes ?? intervalMinutes
        let normalized = AppViewModel.normalizedInterval(hours: nextHours, minutes: nextMinutes)

        isAdjustingIntervalInternally = true
        intervalHours = normalized.hours
        intervalMinutes = normalized.minutes
        isAdjustingIntervalInternally = false

        persistInterval()
        reapplyAutoShuffleIntervalIfNeeded()
        syncState()
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
            autoShuffleStatusText = "运行中（\(formattedIntervalDescription(from: interval))）"
        } else {
            autoShuffleStatusText = "未启动"
        }
    }

    private func handleIntervalComponentChange() {
        guard !isAdjustingIntervalInternally else {
            return
        }
        updateInterval(hours: intervalHours, minutes: intervalMinutes)
    }

    private func reapplyAutoShuffleIntervalIfNeeded() {
        guard shuffleService.isAutoShuffleRunning else {
            return
        }

        shuffleService.startAutoShuffle(interval: effectiveIntervalSeconds) { [weak self] in
            self?.currentShufflePool ?? []
        }
    }

    private func persistInterval() {
        userDefaults.set(intervalHours, forKey: UserDefaultsKey.intervalHours)
        userDefaults.set(intervalMinutes, forKey: UserDefaultsKey.intervalMinutes)
    }

    private func formattedIntervalDescription(from interval: TimeInterval) -> String {
        let totalMinutes = max(Int(interval / 60), 1)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return "每 \(hours) 小时 \(minutes) 分钟"
        }

        if hours > 0 {
            return "每 \(hours) 小时"
        }

        return "每 \(minutes) 分钟"
    }

    private static func normalizedInterval(hours: Int, minutes: Int) -> (hours: Int, minutes: Int) {
        let clampedHours = min(max(hours, 0), 23)
        let clampedMinutes = min(max(minutes, 0), 59)

        if clampedHours == 0, clampedMinutes == 0 {
            return (0, 1)
        }

        return (clampedHours, clampedMinutes)
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
