import SwiftUI

@main
struct YoruMimizukuApp: App {
    @StateObject private var updateController = UpdateController()

    init() {
        MetricsSubscriber.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(updateController)
                .modifier(DebugPerfOverlay())
        }
        .defaultSize(width: 940, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands { NewPostCommands() }
    }
}
