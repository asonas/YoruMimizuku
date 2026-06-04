import SwiftUI
import BlueskyCore
import HoshidukiyoKit

/// Chooses the login screen or the main window based on whether an account is
/// currently stored. Builds the live login stack from the Keychain-backed store.
struct RootView: View {
    @State private var currentDID: String?
    @StateObject private var loginModel: LoginViewModel
    @StateObject private var timelineModel: TimelineViewModel
    @StateObject private var workspace: WorkspaceModel
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var displaySettings = DisplaySettingsStore()

    private let accountManager: AccountManager

    init() {
        let storage = KeychainStorage(service: "as.ason.Hoshidukiyo")
        let manager = AccountManager(store: AccountStore(storage: storage))
        self.accountManager = manager
        _loginModel = StateObject(
            wrappedValue: LoginViewModel(performer: LiveLoginPerformer(accountManager: manager))
        )
        _timelineModel = StateObject(
            wrappedValue: TimelineViewModel(loader: LiveTimelineLoader(accountManager: manager))
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
                MainWindowView(model: timelineModel, workspace: workspace, accountHandle: currentHandle)
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
}
