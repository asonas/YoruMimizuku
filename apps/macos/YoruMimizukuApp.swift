import SwiftUI
import Combine
import BlueskyCore
import PlatformApple
import YoruMimizukuKit

@main
struct YoruMimizukuApp: App {
    private let accountManager: AccountManager
    private let unread: NotificationUnreadStore
    private let dockBadgeSubscription: AnyCancellable
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
    @StateObject private var notificationSettings: NotificationSettingsStore

    init() {
        let manager = AccountManager(store: AccountStore(storage: KeychainStorage(service: "as.ason.YoruMimizuku")))
        let settings = NotificationSettingsStore()
        let unread = NotificationUnreadStore(service: LiveNotificationReadService(accountManager: manager))
        self.accountManager = manager
        self.unread = unread
        _notificationSettings = StateObject(wrappedValue: settings)
        dockBadgeSubscription = unread.$counts.combineLatest(settings.$showsDockBadge)
            .map { counts, enabled in enabled ? counts.values.reduce(0, +) : 0 }
            .removeDuplicates()
            .sink { count in NSApplication.shared.dockTile.badgeLabel = count > 0 ? String(count) : nil }
        MetricsSubscriber.shared.start()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(accountManager: accountManager)
                .environmentObject(unread)
                .environmentObject(updateController)
                .environmentObject(themeStore)
                .environmentObject(displaySettings)
                .environmentObject(fontSettings)
                .environmentObject(notificationSettings)
                .modifier(DebugPerfOverlay())
                .task { updateController.checkForUpdatesOnLaunch() }
        }
        .defaultSize(width: 1240, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            NewPostCommands()
            WorkspaceCommands()
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
        // The standard ⌘, "設定…" menu item now opens this scene automatically —
        // no custom `CommandGroup(replacing: .appSettings)` needed. It shares the
        // same app-level store instances as every `WindowGroup(id: "main")`
        // window, so a change here is immediately visible in any open window and
        // vice versa. `updateController` is not one of the four settings stores
        // but is also app-level already, and the settings screen's アップデート
        // tab (`UpdateSettingsView`) reads it via `@EnvironmentObject`.
        Settings {
            SettingsView()
                .environmentObject(themeStore)
                .environmentObject(displaySettings)
                .environmentObject(fontSettings)
                .environmentObject(notificationSettings)
                .environmentObject(updateController)
                .font(.app(.body))
                .typesettingLanguage(.init(languageCode: .japanese))
        }
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
