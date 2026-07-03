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
                .task { updateController.checkForUpdatesOnLaunch() }
        }
        .defaultSize(width: 940, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands {
            NewPostCommands()
            SettingsCommands()
            #if DEBUG
            CommandGroup(after: .help) {
                OpenCatalogButton()
            }
            #endif
        }
        #if DEBUG
        Window("デザインカタログ", id: "design-catalog") {
            DesignCatalogView()
        }
        #endif
    }
}

#if DEBUG
private struct OpenCatalogButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("デザインカタログ") { openWindow(id: "design-catalog") }
    }
}
#endif
