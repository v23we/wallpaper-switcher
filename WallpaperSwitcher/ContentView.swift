import AppKit
import ImageIO
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    private static let intervalValueFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.generatesDecimalNumbers = false
        formatter.allowsFloats = false
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controlsSection
            statusSection
            wallpapersSection
        }
        .padding(20)
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("Refresh Scan") {
                    viewModel.refreshScan()
                }

                Button("Shuffle Now") {
                    viewModel.shuffleNow()
                }
                .disabled(viewModel.wallpapers.isEmpty)

                Button("Start Auto Shuffle") {
                    viewModel.startAutoShuffle()
                }
                .disabled(viewModel.wallpapers.isEmpty || viewModel.isAutoShuffleRunning)

                Button("Stop Auto Shuffle") {
                    viewModel.stopAutoShuffle()
                }
                .disabled(!viewModel.isAutoShuffleRunning)

                Spacer()

                Picker("Shuffle Scope", selection: $viewModel.selectedShuffleScope) {
                    ForEach(AppViewModel.ShuffleScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Interval")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.intervalPresetOptions) { preset in
                        Button {
                            viewModel.applyIntervalPreset(preset)
                        } label: {
                            Text(preset.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(viewModel.activeIntervalPreset == preset ? Color.accentColor : Color.primary.opacity(0.78))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(
                                            viewModel.activeIntervalPreset == preset
                                            ? Color.accentColor.opacity(0.10)
                                            : Color(NSColor.controlBackgroundColor)
                                        )
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            viewModel.activeIntervalPreset == preset
                                            ? Color.accentColor.opacity(0.22)
                                            : Color.primary.opacity(0.08),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(alignment: .center, spacing: 8) {
                    Text("Custom")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)

                    TextField(
                        "",
                        value: Binding(
                            get: { viewModel.intervalDays },
                            set: { viewModel.updateInterval(days: $0) }
                        ),
                        formatter: Self.intervalValueFormatter
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)

                    Text("d")
                        .foregroundStyle(.secondary)

                    TextField(
                        "",
                        value: Binding(
                            get: { viewModel.intervalHours },
                            set: { viewModel.updateInterval(hours: $0) }
                        ),
                        formatter: Self.intervalValueFormatter
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)

                    Text("h")
                        .foregroundStyle(.secondary)

                    TextField(
                        "",
                        value: Binding(
                            get: { viewModel.intervalMinutes },
                            set: { viewModel.updateInterval(minutes: $0) }
                        ),
                        formatter: Self.intervalValueFormatter
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)

                    Text("min")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusSection: some View {
        GroupBox("状态") {
            VStack(alignment: .leading, spacing: 10) {
                StatusRow(title: "当前扫描总数", value: "\(viewModel.wallpaperCount)")
                StatusRow(title: "当前生效壁纸", value: viewModel.currentWallpaperPath)
                StatusRow(title: "当前 Shuffle 范围", value: viewModel.currentShuffleScopeText)
                StatusRow(title: "最近错误信息", value: viewModel.lastErrorMessage)
                StatusRow(title: "自动轮换状态", value: viewModel.autoShuffleStatusText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var wallpapersSection: some View {
        if viewModel.wallpapers.isEmpty {
            GroupBox("扫描结果") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("未扫描到壁纸资源")
                        .font(.headline)

                    Text("尝试过的路径：")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.attemptedPaths, id: \.self) { path in
                        Text(path)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !viewModel.dynamicItems.isEmpty {
                        WallpaperSectionView(
                            title: "Dynamic Wallpapers",
                            items: viewModel.dynamicItems,
                            isActive: viewModel.selectedShuffleScope == .dynamic,
                            currentWallpaperPath: viewModel.currentWallpaperPath,
                            onSelect: viewModel.applyWallpaper
                        )
                    }

                    if !viewModel.pictureItems.isEmpty {
                        WallpaperSectionView(
                            title: "Pictures",
                            items: viewModel.pictureItems,
                            isActive: viewModel.selectedShuffleScope == .pictures,
                            currentWallpaperPath: viewModel.currentWallpaperPath,
                            onSelect: viewModel.applyWallpaper
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct WallpaperSectionView: View {
    let title: String
    let items: [WallpaperItem]
    let isActive: Bool
    let currentWallpaperPath: String
    let onSelect: (WallpaperItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)
    ]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text("\(title) (\(items.count))")
                        .font(.headline)

                    if isActive {
                        Text("active")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.quaternaryLabelColor).opacity(0.08))
                            .clipShape(Capsule())
                    }
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            WallpaperCardView(
                                item: item,
                                isCurrentWallpaper: item.fileURL.path == currentWallpaperPath
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

private struct StatusRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct WallpaperCardView: View {
    let item: WallpaperItem
    let isCurrentWallpaper: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isCurrentWallpaper {
                Capsule()
                    .fill(Color.accentColor.opacity(0.82))
                    .frame(height: 3)
                    .padding(.bottom, 2)
            }

            Rectangle()
                .fill(Color.clear)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay {
                    Image(nsImage: ThumbnailProvider.thumbnail(for: item.fileURL))
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isCurrentWallpaper
                                    ? Color.accentColor.opacity(0.28)
                                    : Color.black.opacity(0.05),
                                lineWidth: isCurrentWallpaper ? 1.2 : 1
                            )

                        if isCurrentWallpaper {
                            Text("Current")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(NSColor.windowBackgroundColor).opacity(0.96))
                                .overlay {
                                    Capsule()
                                        .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                                }
                                .clipShape(Capsule())
                                .padding(8)
                        }
                    }
                }
                .clipped()

            Text(item.fileName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            ItemBadge(text: item.categoryGuess.rawValue)

            Text(item.fileURL.path)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isCurrentWallpaper
                        ? Color.accentColor.opacity(0.34)
                        : Color.black.opacity(0.06),
                    lineWidth: isCurrentWallpaper ? 1.2 : 1
                )
        }
        .shadow(
            color: .black.opacity(isCurrentWallpaper ? 0.08 : 0.035),
            radius: isCurrentWallpaper ? 9 : 5,
            y: isCurrentWallpaper ? 3 : 2
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ItemBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(.secondary)
            .background(Color(NSColor.quaternaryLabelColor).opacity(0.08))
            .clipShape(Capsule())
    }
}

private enum ThumbnailProvider {
    private static let cache = NSCache<NSURL, NSImage>()

    static func thumbnail(for fileURL: URL, maxPixelSize: CGFloat = 240) -> NSImage {
        if let cachedImage = cache.object(forKey: fileURL as NSURL) {
            return cachedImage
        }

        if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
                kCGImageSourceCreateThumbnailWithTransform: true
            ]

            if let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) {
                let image = NSImage(cgImage: cgImage, size: .zero)
                cache.setObject(image, forKey: fileURL as NSURL)
                return image
            }
        }

        let fallback = NSWorkspace.shared.icon(forFile: fileURL.path)
        fallback.size = NSSize(width: 84, height: 52)
        cache.setObject(fallback, forKey: fileURL as NSURL)
        return fallback
    }
}
