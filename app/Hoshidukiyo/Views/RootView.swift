import SwiftUI
import BlueskyCore
import HoshidukiyoKit

/// Chooses the login screen or the main window based on whether an account is
/// currently stored. Builds the live login stack from the Keychain-backed store.
struct RootView: View {
    @State private var currentDID: String?
    @StateObject private var loginModel: LoginViewModel
    @StateObject private var timelineModel: TimelineViewModel

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
        // current() returns PersistedAccount?; try? wraps it again, so flatten first.
        let existing = (try? manager.current()) ?? nil
        _currentDID = State(initialValue: existing?.did)
    }

    var body: some View {
        Group {
            if currentDID != nil {
                MainWindowView(model: timelineModel, accountHandle: currentHandle)
            } else {
                LoginView(model: loginModel) { did in
                    currentDID = did
                }
            }
        }
    }

    /// Handle of the current account for the account chip; falls back to the DID.
    private var currentHandle: String {
        let account = (try? accountManager.current()) ?? nil
        return account?.handle ?? account?.did ?? ""
    }
}
