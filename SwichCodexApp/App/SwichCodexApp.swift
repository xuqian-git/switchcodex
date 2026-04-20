import SwiftUI

@main
struct SwichCodexApp: App {
    @StateObject private var rootViewModel = RootViewModel.live()

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: rootViewModel)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            SidebarCommands()
        }
    }
}
