import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    private struct CachedWallpaperItem: Codable {
        let filePath: String
        let categoryGuessRawValue: String
    }

    struct IntervalPreset: Identifiable, Hashable {
        let label: String
        let days: Int
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
    @Published private(set) var isInitialLoading = true
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var cachedItemsLoaded = false
    @Published var selectedShuffleScope: ShuffleScope = .all
    @Published var intervalDays: Int {
        didSet {
            handleIntervalComponentChange()
        }
    }
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
        IntervalPreset(label: "1m", days: 0, hours: 0, minutes: 1),
        IntervalPreset(label: "5m", days: 0, hours: 0, minutes: 5),
        IntervalPreset(label: "15m", days: 0, hours: 0, minutes: 15),
        IntervalPreset(label: "30m", days: 0, hours: 0, minutes: 30),
        IntervalPreset(label: "1h", days: 0, hours: 1, minutes: 0),
        IntervalPreset(label: "2h", days: 0, hours: 2, minutes: 0),
        IntervalPreset(label: "24h", days: 1, hours: 0, minutes: 0)
    ]

    private enum UserDefaultsKey {
        static let cachedWallpaperItems = "WallpaperSwitcher.cachedWallpaperItems"
        static let intervalDays = "WallpaperSwitcher.intervalDays"
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

        let storedDaysObject = userDefaults.object(forKey: UserDefaultsKey.intervalDays)
        let storedHoursObject = userDefaults.object(forKey: UserDefaultsKey.intervalHours)
        let storedMinutesObject = userDefaults.object(forKey: UserDefaultsKey.intervalMinutes)
        let storedDays = storedDaysObject == nil ? 0 : userDefaults.integer(forKey: UserDefaultsKey.intervalDays)
        let storedHours = storedHoursObject == nil ? 0 : userDefaults.integer(forKey: UserDefaultsKey.intervalHours)
        let storedMinutes = storedMinutesObject == nil ? 5 : userDefaults.integer(forKey: UserDefaultsKey.intervalMinutes)
        let normalized = AppViewModel.normalizeInterval(days: storedDays, hours: storedHours, minutes: storedMinutes)
        self.intervalDays = normalized.days
        self.intervalHours = normalized.hours
        self.intervalMinutes = normalized.minutes
    }

    func initialLoad() {
        shuffleService.refreshCurrentWallpaper()
        loadCachedWallpapersIfAvailable()
        syncState()
        refreshScan(isInitialLoad: true)
    }

    func refreshScan(isInitialLoad: Bool = false) {
        if isInitialLoad && !cachedItemsLoaded {
            isInitialLoading = true
        }

        Task { [weak self, scanner] in
            let result = await Task.detached(priority: .userInitiated) {
                scanner.scan()
            }.value

            await MainActor.run {
                self?.applyScanResult(result, markInitialLoadCompleted: true)
            }
        }
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
        TimeInterval((intervalDays * 24 * 3600) + (intervalHours * 3600) + (intervalMinutes * 60))
    }

    var intervalPresetOptions: [IntervalPreset] {
        Self.intervalPresets
    }

    var activeIntervalPreset: IntervalPreset? {
        Self.intervalPresets.first { preset in
            preset.days == intervalDays && preset.hours == intervalHours && preset.minutes == intervalMinutes
        }
    }

    func applyIntervalPreset(_ preset: IntervalPreset) {
        updateInterval(days: preset.days, hours: preset.hours, minutes: preset.minutes)
    }

    func updateInterval(days: Int? = nil, hours: Int? = nil, minutes: Int? = nil) {
        let nextDays = days ?? intervalDays
        let nextHours = hours ?? intervalHours
        let nextMinutes = minutes ?? intervalMinutes
        let normalized = AppViewModel.normalizeInterval(days: nextDays, hours: nextHours, minutes: nextMinutes)

        isAdjustingIntervalInternally = true
        intervalDays = normalized.days
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

    private func applyScanResult(_ result: WallpaperScanner.ScanResult, markInitialLoadCompleted: Bool) {
        wallpapers = result.items
        rebuildSections(from: result.items)
        attemptedPaths = result.attemptedPaths
        wallpaperCount = result.items.count

        if result.items.isEmpty {
            latestScanMessage = result.warnings.isEmpty ? "未扫描到壁纸资源" : result.warnings.joined(separator: "\n")
        } else {
            latestScanMessage = result.warnings.isEmpty ? nil : result.warnings.joined(separator: "\n")
        }

        persistCachedWallpapers(result.items)

        if markInitialLoadCompleted {
            isInitialLoading = false
            hasLoadedOnce = true
        }

        if shuffleService.isAutoShuffleRunning {
            shuffleService.startAutoShuffle(interval: effectiveIntervalSeconds) { [weak self] in
                self?.currentShufflePool ?? []
            }
        }

        syncState()
    }

    private func handleIntervalComponentChange() {
        guard !isAdjustingIntervalInternally else {
            return
        }
        updateInterval(days: intervalDays, hours: intervalHours, minutes: intervalMinutes)
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
        userDefaults.set(intervalDays, forKey: UserDefaultsKey.intervalDays)
        userDefaults.set(intervalHours, forKey: UserDefaultsKey.intervalHours)
        userDefaults.set(intervalMinutes, forKey: UserDefaultsKey.intervalMinutes)
    }

    private func loadCachedWallpapersIfAvailable() {
        let cachedItems = restoreCachedWallpapers()
        guard !cachedItems.isEmpty else {
            cachedItemsLoaded = false
            return
        }

        wallpapers = cachedItems
        rebuildSections(from: cachedItems)
        wallpaperCount = cachedItems.count
        cachedItemsLoaded = true
        hasLoadedOnce = true
        isInitialLoading = false
    }

    private func restoreCachedWallpapers() -> [WallpaperItem] {
        guard let data = userDefaults.data(forKey: UserDefaultsKey.cachedWallpaperItems),
              let cachedItems = try? JSONDecoder().decode([CachedWallpaperItem].self, from: data) else {
            return []
        }

        let fileManager = FileManager.default
        return cachedItems.compactMap { cachedItem in
            guard fileManager.fileExists(atPath: cachedItem.filePath),
                  let categoryGuess = WallpaperItem.CategoryGuess(rawValue: cachedItem.categoryGuessRawValue) else {
                return nil
            }

            return WallpaperItem(fileURL: URL(fileURLWithPath: cachedItem.filePath), categoryGuess: categoryGuess)
        }
    }

    private func persistCachedWallpapers(_ items: [WallpaperItem]) {
        let cachedItems = items.map {
            CachedWallpaperItem(filePath: $0.fileURL.path, categoryGuessRawValue: $0.categoryGuess.rawValue)
        }

        if let data = try? JSONEncoder().encode(cachedItems) {
            userDefaults.set(data, forKey: UserDefaultsKey.cachedWallpaperItems)
        }
    }

    private func formattedIntervalDescription(from interval: TimeInterval) -> String {
        let totalMinutes = max(Int(interval / 60), 1)
        let days = totalMinutes / (24 * 60)
        let remainingMinutesAfterDays = totalMinutes % (24 * 60)
        let hours = remainingMinutesAfterDays / 60
        let minutes = remainingMinutesAfterDays % 60
        var components: [String] = []

        if days > 0 {
            components.append("\(days) 天")
        }

        if hours > 0 {
            components.append("\(hours) 小时")
        }

        if minutes > 0 {
            components.append("\(minutes) 分钟")
        }

        return "每 " + components.joined(separator: " ")
    }

    private static func normalizeInterval(days: Int, hours: Int, minutes: Int) -> (days: Int, hours: Int, minutes: Int) {
        let safeDays = max(days, 0)
        let safeHours = max(hours, 0)
        let safeMinutes = max(minutes, 0)
        let maxTotalMinutes = ((99 * 24) + 23) * 60 + 59
        var totalMinutes = (safeDays * 24 * 60) + (safeHours * 60) + safeMinutes

        if totalMinutes <= 0 {
            totalMinutes = 1
        }

        totalMinutes = min(totalMinutes, maxTotalMinutes)

        let normalizedDays = totalMinutes / (24 * 60)
        let remainingMinutes = totalMinutes % (24 * 60)
        let normalizedHours = remainingMinutes / 60
        let normalizedMinutes = remainingMinutes % 60

        return (normalizedDays, normalizedHours, normalizedMinutes)
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
