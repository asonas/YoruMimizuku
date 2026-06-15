import SwiftUI

@main
struct YoruMimizukuApp: App {
    /// Quit-event handling for Sparkle's "Install and Restart"; see AppDelegate.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
        .commands {
            NewPostCommands()
            SettingsCommands()
        }
    }
}
