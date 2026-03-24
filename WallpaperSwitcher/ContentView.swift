import AppKit
import ImageIO
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controlsSection
            statusSection
            wallpapersSection
        }
        .padding(20)
    }

    private var controlsSection: some View {
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

            Picker("Interval", selection: $viewModel.selectedInterval) {
                ForEach(AppViewModel.ShuffleInterval.allCases) { interval in
                    Text(interval.rawValue).tag(interval)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
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
                            onSelect: viewModel.applyWallpaper
                        )
                    }

                    if !viewModel.pictureItems.isEmpty {
                        WallpaperSectionView(
                            title: "Pictures",
                            items: viewModel.pictureItems,
                            isActive: viewModel.selectedShuffleScope == .pictures,
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
    let onSelect: (WallpaperItem) -> Void

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

                ForEach(items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        WallpaperRowView(item: item)
                    }
                    .buttonStyle(.plain)
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

private struct WallpaperRowView: View {
    let item: WallpaperItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: ThumbnailProvider.thumbnail(for: item.fileURL))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 84, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.fileName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(item.fileURL.path)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                ItemBadge(text: item.categoryGuess.rawValue)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
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
