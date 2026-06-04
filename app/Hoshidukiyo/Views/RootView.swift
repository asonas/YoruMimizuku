import SwiftUI
import BlueskyCore
import HoshidukiyoKit

/// Chooses the login screen or the main window based on whether an account is
/// currently stored. Builds the live login stack from the Keychain-backed store.
struct RootView: View {
    @State private var currentDID: String?
    @State private var accountAvatarURL: URL?
    @StateObject private var loginModel: LoginViewModel
    @StateObject private var timelineModel: TimelineViewModel
    @StateObject private var notificationsModel: NotificationsViewModel
    @StateObject private var workspace: WorkspaceModel
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var displaySettings = DisplaySettingsStore()

    private let accountManager: AccountManager
    private let profileLoader: LiveProfileLoader

    init() {
        let storage = KeychainStorage(service: "as.ason.Hoshidukiyo")
        let manager = AccountManager(store: AccountStore(storage: storage))
        self.accountManager = manager
        self.profileLoader = LiveProfileLoader(accountManager: manager)
        _loginModel = StateObject(
            wrappedValue: LoginViewModel(performer: LiveLoginPerformer(accountManager: manager))
        )
        _timelineModel = StateObject(
            wrappedValue: TimelineViewModel(loader: LiveTimelineLoader(accountManager: manager))
        )
        _notificationsModel = StateObject(
            wrappedValue: NotificationsViewModel(loader: LiveNotificationsLoader(accountManager: manager))
        )
        _workspace = StateObject(
            wrappedValue: WorkspaceModel { uri in
                ThreadViewModel(loader: LiveThreadLoader(accountManager: manager), uri: uri)
            }
        )
        // current() returns PersistedAccount?; try? wraps it again, so flatten first.
        let existing = (try? manager.current()) ?? nil
        _currentDID = State(initialValue: existing?.did)
    }

    var body: some View {
        Group {
            if currentDID != nil {
                MainWindowView(
                    model: timelineModel,
                    notifications: notificationsModel,
                    workspace: workspace,
                    accountHandle: currentHandle,
                    accountAvatarURL: accountAvatarURL
                )
                .task(id: currentDID) { await loadAvatar() }
            } else {
                LoginView(model: loginModel) { did in
                    currentDID = did
                }
            }
        }
        .environmentObject(themeStore)
        .environmentObject(displaySettings)
    }

    /// Handle of the current account for the account chip; falls back to the DID.
    private var currentHandle: String {
        let account = (try? accountManager.current()) ?? nil
        return account?.handle ?? account?.did ?? ""
    }

    /// Resolve the signed-in account's avatar; failures leave the placeholder in
    /// place since the avatar is cosmetic.
    private func loadAvatar() async {
        accountAvatarURL = try? await profileLoader.loadCurrentAvatar()
    }
}
