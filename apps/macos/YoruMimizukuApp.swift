import SwiftUI

@main
struct YoruMimizukuApp: App {
    /// Quit-event handling for Sparkle's "Install and Restart"; see AppDelegate.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var updateController = UpdateController()
    /// The four settings stores, owned at the app level (not per-window) so every
    /// open `WindowGroup(id: "main")` window and the `Settings` scene share the
    /// same instances: a change in one place is instantly visible everywhere,
    /// since all read/write the same `@Published` state rather than independently
    /// re-reading `UserDefaults` at their own init.
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var displaySettings = DisplaySettingsStore()
    @StateObject private var fontSettings = FontSettingsStore()
    @StateObject private var notificationSettings = NotificationSettingsStore()

    init() {
        MetricsSubscriber.shared.start()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(updateController)
                .environmentObject(themeStore)
                .environmentObject(displaySettings)
                .environmentObject(fontSettings)
                .environmentObject(notificationSettings)
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
