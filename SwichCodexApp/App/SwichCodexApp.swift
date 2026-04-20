import AppKit
import SwiftUI

@main
struct SwichCodexApp: App {
    @StateObject private var rootViewModel = RootViewModel.live()

    var body: some Scene {
        WindowGroup("SwichCodex", id: "main") {
            RootView(viewModel: rootViewModel)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            SidebarCommands()
        }

        MenuBarExtra("SwichCodex", systemImage: "arrow.left.arrow.right.circle.fill") {
            MenuBarPanelView(rootViewModel: rootViewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
