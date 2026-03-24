import SwiftUI

@main
struct WallpaperSwitcherApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 780, minHeight: 620)
                .task {
                    viewModel.initialLoad()
                }
        }
    }
}
