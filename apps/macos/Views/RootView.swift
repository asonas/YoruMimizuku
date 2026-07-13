import AppKit
import Combine
import os
import SwiftUI
import BlueskyCore
import YoruMimizukuKit
import PlatformApple

/// Chooses the login screen or the authenticated UI based on whether an account is
/// currently stored. The authenticated subtree is rebuilt per account DID so the
/// filter store and feeds are always scoped to the real account — including a first
/// login in this same launch and account switches.
struct RootView: View {
    @State private var currentDID: String?
    @State private var accountAvatarURL: URL?
    /// True while the "add account" login sheet is presented over the signed-in UI.
    @State private var isAddingAccount = false
    @StateObject private var loginModel: LoginViewModel
    /// The pending re-auth request for the expired current account (nil when the
    /// session is healthy). Persists across a sheet cancel so the banner stays.
    @State private var reauth: ReauthRequest?
    /// Drives the re-auth login sheet; separate from `isAddingAccount` so the two
    /// flows never interfere.
    @State private var isReauthSheetShown = false
    /// Bumped on each successful re-auth and folded into the authenticated
    /// subtree's `.id`, forcing an immediate rebuild + fresh load with new tokens.
    @State private var reauthGeneration = 0
    /// A login model dedicated to re-auth, pre-filled with the expired handle.
    @StateObject private var reauthLoginModel: LoginViewModel
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var displaySettings = DisplaySettingsStore()
    @StateObject private var fontSettings = FontSettingsStore()
    @StateObject private var notificationSettings = NotificationSettingsStore()

    private let accountManager: AccountManager
    private let profileLoader: LiveProfileLoader
    private static let log = Logger(subsystem: PerfSignpost.subsystem, category: "Session")

    init() {
        let storage = KeychainStorage(service: "as.ason.YoruMimizuku")
        let manager = AccountManager(store: AccountStore(storage: storage))
        self.accountManager = manager
        self.profileLoader = LiveProfileLoader(accountManager: manager)

        _loginModel = StateObject(
            wrappedValue: LoginViewModel(performer: LiveLoginPerformer(accountManager: manager))
        )
        _reauthLoginModel = StateObject(
            wrappedValue: LoginViewModel(performer: LiveLoginPerformer(accountManager: manager))
        )
        // current() returns PersistedAccount?; try? wraps it again, so flatten first.
        let existing = (try? manager.current()) ?? nil
        _currentDID = State(initialValue: existing?.did)
    }

    var body: some View {
        VStack(spacing: 0) {
            if reauth != nil {
                SessionReauthBanner(onReauth: { isReauthSheetShown = true })
            }
            Group {
                if let did = currentDID {
                    AuthenticatedRootView(
                        accountManager: accountManager,
                        did: did,
                        accountHandle: currentHandle,
                        accountAvatarURL: accountAvatarURL,
                        accounts: accounts,
                        onSwitchAccount: { switchAccount(to: $0) },
                        onAddAccount: { startAddAccount() },
                        onLogout: { logout() },
                        makeComposer: { parent in
                            ComposerViewModel(submitter: LiveComposer(accountManager: accountManager), replyParent: parent)
                        },
                        makeQuoteComposer: { post in
                            ComposerViewModel(submitter: LiveComposer(accountManager: accountManager), quotedPost: post)
                        }
                    )
                    .id("\(did)#\(reauthGeneration)")
                    .task(id: currentDID) { await loadAvatar() }
                } else {
                    LoginView(model: loginModel) { did in
                        currentDID = did
                    }
                }
            }
        }
        .environmentObject(themeStore)
        .environmentObject(displaySettings)
        .environmentObject(fontSettings)
        .environmentObject(notificationSettings)
        // Establish the app-wide base font and Japanese typesetting so line metrics
        // and glyph selection are correct regardless of UI locale.
        .font(.app(.body))
        .typesettingLanguage(.init(languageCode: .japanese))
        // A dead refresh token can't be recovered by retrying; keep the account
        // and prompt the user to re-authenticate via the banner + sheet.
        .onReceive(NotificationCenter.default.publisher(for: SessionExpiry.notification)) { _ in
            handleSessionExpired()
        }
        // On wake from sleep the polling tasks were suspended and the access token
        // has likely expired, so the first post-wake request would 401 (and several
        // pollers could race to refresh the single-use token). Refresh the session
        // proactively and up front instead. `didWakeNotification` is posted on the
        // workspace's own center, not `NotificationCenter.default`.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            refreshSessionOnWake()
        }
        // The "add account" login flow, presented over the signed-in UI. On success
        // the new account is current (AccountManager.add sets it), so adopting its
        // DID rebuilds the authenticated subtree for the new account.
        .sheet(isPresented: $isAddingAccount) {
            LoginView(model: loginModel) { did in
                isAddingAccount = false
                currentDID = did
            }
            .environmentObject(themeStore)
            .frame(minWidth: 420, minHeight: 360)
        }
        .sheet(isPresented: $isReauthSheetShown) {
            LoginView(model: reauthLoginModel) { did in
                reauth = nil
                isReauthSheetShown = false
                reauthGeneration += 1
                accountAvatarURL = nil
                currentDID = did
            }
            .environmentObject(themeStore)
            .frame(minWidth: 420, minHeight: 360)
        }
    }

    /// Proactively refresh the current account's session when the machine wakes.
    /// On success the new tokens are persisted, so the imminent poll uses a live
    /// token. An `invalid_grant` means the refresh token died while asleep; it is
    /// reported through `SessionExpiry`, which prompts re-auth via the handler
    /// above. Other errors (e.g. the network not yet up on wake) are left for the
    /// next request's reactive refresh to retry. Never logs token material.
    private func refreshSessionOnWake() {
        guard currentDID != nil else { return }
        let manager = accountManager
        Task {
            do {
                let context = try LiveServiceContext(accountManager: manager, config: .yoruMimizuku)
                try await context.refreshSession()
                Self.log.info("Proactive session refresh on wake succeeded")
            } catch {
                if SessionExpiry.reportIfExpired(error) {
                    Self.log.notice("Session expired while asleep; prompting re-auth")
                } else {
                    Self.log.error("Wake refresh failed; the next request will retry reactively")
                }
            }
        }
    }

    /// Keep the account whose session can no longer be refreshed, and prompt the
    /// user to re-authenticate via the banner + sheet instead of dropping it.
    private func handleSessionExpired() {
        guard let request = SessionReauth.onExpiry(
            currentDID: currentDID,
            currentHandle: currentHandle,
            isPending: reauth != nil
        ) else { return }
        Self.log.notice("Session expired; prompting re-auth")
        reauth = request
        reauthLoginModel.reset()
        reauthLoginModel.handle = request.handle
        isReauthSheetShown = true
    }

    /// Switch the active account to `did` and rebuild the signed-in subtree for it.
    private func switchAccount(to did: String) {
        guard did != currentDID else { return }
        try? accountManager.switchTo(did: did)
        reauth = nil
        isReauthSheetShown = false
        currentDID = did
    }

    /// Open the login flow to add another account. Reset the shared login model so
    /// the sheet starts blank rather than showing the previous login's state.
    private func startAddAccount() {
        loginModel.reset()
        isAddingAccount = true
    }

    /// Log out of the current account: remove it (clearing its Keychain item) and
    /// fall through to the next stored account, or the login screen when none remain.
    private func logout() {
        guard let did = currentDID else { return }
        reauth = nil
        isReauthSheetShown = false
        currentDID = (try? accountManager.removeAndAdvance(did: did)) ?? nil
    }

    /// The stored accounts for the switcher menu. Empty if the read fails.
    private var accounts: [AccountSummary] {
        (try? accountManager.summaries()) ?? []
    }

    private var currentHandle: String {
        let account = (try? accountManager.current()) ?? nil
        return account?.handle ?? account?.did ?? ""
    }

    private func loadAvatar() async {
        accountAvatarURL = try? await profileLoader.loadCurrentAvatar()
    }
}

/// The signed-in UI for one account. Built per DID (via `.id(did)` in `RootView`)
/// so its `TimelineViewModel`, notifications, and the per-account filter store are
/// always created with the real account DID.
private struct AuthenticatedRootView: View {
    @StateObject private var timelineModel: TimelineViewModel
    @StateObject private var notificationsModel: NotificationsViewModel
    @StateObject private var workspace: WorkspaceModel

    private let accountDID: String
    private let accountHandle: String
    private let accountAvatarURL: URL?
    private let accounts: [AccountSummary]
    private let onSwitchAccount: (String) -> Void
    private let onAddAccount: () -> Void
    private let onLogout: () -> Void
    private let makeComposer: @MainActor (PostDisplay?) -> ComposerViewModel
    private let makeQuoteComposer: @MainActor (PostDisplay) -> ComposerViewModel

    init(
        accountManager: AccountManager,
        did: String,
        accountHandle: String,
        accountAvatarURL: URL?,
        accounts: [AccountSummary],
        onSwitchAccount: @escaping (String) -> Void,
        onAddAccount: @escaping () -> Void,
        onLogout: @escaping () -> Void,
        makeComposer: @escaping @MainActor (PostDisplay?) -> ComposerViewModel,
        makeQuoteComposer: @escaping @MainActor (PostDisplay) -> ComposerViewModel
    ) {
        _timelineModel = StateObject(
            wrappedValue: TimelineViewModel(
                loader: LiveTimelineLoader(accountManager: accountManager),
                interactor: LivePostInteractor(accountManager: accountManager),
                tracer: OSSignpostTracing.timeline
            )
        )
        _notificationsModel = StateObject(
            wrappedValue: NotificationsViewModel(loader: LiveNotificationsLoader(accountManager: accountManager))
        )
        let filterStore = SavedFilterStore(port: FilterFileStore(did: did))
        _workspace = StateObject(
            wrappedValue: WorkspaceModel(
                filterStore: filterStore,
                persistence: UserDefaultsConversationStore(key: "workspace.conversations.v1.\(did)"),
                makeThreadModel: { uri in
                    ThreadViewModel(
                        loader: LiveThreadLoader(accountManager: accountManager), uri: uri,
                        interactor: LivePostInteractor(accountManager: accountManager)
                    )
                },
                makeFilterModel: { filter in
                    TimelineViewModel(loader: LiveSearchLoader(accountManager: accountManager, subqueries: filter.subqueries))
                },
                makeAuthorModel: { authorDID in
                    TimelineViewModel(
                        loader: LiveAuthorFeedLoader(accountManager: accountManager, actor: authorDID),
                        interactor: LivePostInteractor(accountManager: accountManager)
                    )
                },
                makeAuthorHeader: { authorDID, initial in
                    ProfileHeaderViewModel(
                        loader: LiveAuthorProfileLoader(accountManager: accountManager),
                        actor: authorDID,
                        initial: initial
                    )
                }
            )
        )
        self.accountDID = did
        self.accountHandle = accountHandle
        self.accountAvatarURL = accountAvatarURL
        self.accounts = accounts
        self.onSwitchAccount = onSwitchAccount
        self.onAddAccount = onAddAccount
        self.onLogout = onLogout
        self.makeComposer = makeComposer
        self.makeQuoteComposer = makeQuoteComposer
    }

    var body: some View {
        MainWindowView(
            model: timelineModel,
            notifications: notificationsModel,
            workspace: workspace,
            accountHandle: accountHandle,
            accountAvatarURL: accountAvatarURL,
            accountDID: accountDID,
            accounts: accounts,
            onSwitchAccount: onSwitchAccount,
            onAddAccount: onAddAccount,
            onLogout: onLogout,
            makeComposer: makeComposer,
            makeQuoteComposer: makeQuoteComposer
        )
    }
}
