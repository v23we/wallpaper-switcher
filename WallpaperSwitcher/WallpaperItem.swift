import Foundation

struct WallpaperItem: Identifiable, Hashable {
    enum CategoryGuess: String, CaseIterable {
        case picture
        case dynamic
        case unknown
    }

    let id: String
    let fileURL: URL
    let fileName: String
    let categoryGuess: CategoryGuess
    let isHEIC: Bool

    init(fileURL: URL, categoryGuess: CategoryGuess) {
        let normalizedURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        self.id = normalizedURL.path
        self.fileURL = normalizedURL
        self.fileName = normalizedURL.lastPathComponent
        self.categoryGuess = categoryGuess
        self.isHEIC = normalizedURL.pathExtension.lowercased() == "heic"
    }
}
