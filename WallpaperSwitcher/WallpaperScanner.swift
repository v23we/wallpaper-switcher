import Foundation

struct WallpaperScanner {
    struct ScanResult {
        let items: [WallpaperItem]
        let attemptedPaths: [String]
        let warnings: [String]
    }

    private let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
    private let solidColorsDirectoryPrefix = "/System/Library/Desktop Pictures/Solid Colors/"
    private let globallyExcludedWallpaperFilenames: Set<String> = [
        "Sequoia Sunrise.heic",
        "Sonoma Horizon.heic"
    ]

    func scan() -> ScanResult {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser

        let scanRoots: [URL] = [
            URL(fileURLWithPath: "/System/Library/Desktop Pictures", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/Desktop Pictures/.wallpapers", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Application Support/com.apple.mobileAssetDesktop", isDirectory: true)
        ]
        let auxiliaryPaths: [URL] = [
            homeDirectory.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist", isDirectory: false)
        ]

        var attemptedPaths: [String] = []
        var warnings: [String] = []
        var itemsByID: [String: WallpaperItem] = [:]
        var solidColorsFilteredCount = 0
        var globallyExcludedCount = 0

        for root in scanRoots {
            attemptedPaths.append(root.path)

            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
                warnings.append("未找到扫描目录: \(root.path)")
                continue
            }

            guard isDirectory.boolValue else {
                warnings.append("扫描目标不是目录: \(root.path)")
                continue
            }

            let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey]
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsPackageDescendants],
                errorHandler: { url, error in
                    warnings.append("扫描失败: \(url.path) (\(error.localizedDescription))")
                    return true
                }
            )

            while let nextObject = enumerator?.nextObject() as? URL {
                let standardizedURL = nextObject.standardizedFileURL.resolvingSymlinksInPath()
                let pathComponents = standardizedURL.pathComponents

                if pathComponents.contains(".thumbnails") {
                    enumerator?.skipDescendants()
                    continue
                }

                do {
                    let resourceValues = try standardizedURL.resourceValues(forKeys: resourceKeys)
                    if resourceValues.isDirectory == true {
                        continue
                    }

                    guard resourceValues.isRegularFile == true else {
                        continue
                    }
                } catch {
                    warnings.append("读取文件属性失败: \(standardizedURL.path) (\(error.localizedDescription))")
                    continue
                }

                let fileExtension = standardizedURL.pathExtension.lowercased()
                guard supportedExtensions.contains(fileExtension) else {
                    continue
                }

                if globallyExcludedWallpaperFilenames.contains(standardizedURL.lastPathComponent) {
                    globallyExcludedCount += 1
                    continue
                }

                // 这是针对 macOS 系统纯色壁纸目录的启发式过滤，不保证未来系统版本稳定。
                if standardizedURL.path.hasPrefix(solidColorsDirectoryPrefix) {
                    solidColorsFilteredCount += 1
                    continue
                }

                // 这是启发式过滤：系统目录里存在用于 UI 的缩略图资源，不应被当成真正桌面图候选。
                if standardizedURL.lastPathComponent.localizedCaseInsensitiveContains("thumbnail") {
                    continue
                }

                let categoryGuess = category(for: standardizedURL)
                let item = WallpaperItem(fileURL: standardizedURL, categoryGuess: categoryGuess)
                itemsByID[item.id] = item
            }
        }

        for auxiliaryPath in auxiliaryPaths {
            attemptedPaths.append(auxiliaryPath.path)
            if !fileManager.fileExists(atPath: auxiliaryPath.path) {
                warnings.append("辅助调试路径不存在: \(auxiliaryPath.path)")
            }
        }

        let items = itemsByID.values.sorted {
            $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending
        }

        print("WallpaperScanner: filtered \(solidColorsFilteredCount) item(s) from Solid Colors.")
        print("WallpaperScanner: filtered \(globallyExcludedCount) item(s) from global exclusion list.")

        return ScanResult(items: items, attemptedPaths: attemptedPaths, warnings: warnings)
    }

    private func category(for fileURL: URL) -> WallpaperItem.CategoryGuess {
        let path = fileURL.path

        // 这是按“真动态壁纸”收紧后的启发式分类。
        // 当前只把 mobileAssetDesktop 下的资源视为 true dynamic。
        // 这仍然是启发式规则，不是 Apple 承诺稳定的公开接口。
        if path.contains("com.apple.mobileAssetDesktop") {
            return .dynamic
        }

        if path.contains("/Desktop Pictures") {
            return .picture
        }

        return .unknown
    }
}
