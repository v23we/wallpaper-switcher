import SwiftUI

@main
struct WallpaperSwitcherApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 980, minHeight: 700)
                .task {
                    viewModel.initialLoad()
                }
        }
    }
}
