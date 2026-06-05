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
    @StateObject private var loginModel: LoginViewModel
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var displaySettings = DisplaySettingsStore()
    @StateObject private var fontSettings = FontSettingsStore()

    private let accountManager: AccountManager
    private let profileLoader: LiveProfileLoader

    init() {
        let storage = KeychainStorage(service: "as.ason.YoruMimizuku")
        let manager = AccountManager(store: AccountStore(storage: storage))
        self.accountManager = manager
        self.profileLoader = LiveProfileLoader(accountManager: manager)

        _loginModel = StateObject(
            wrappedValue: LoginViewModel(performer: LiveLoginPerformer(accountManager: manager))
        )
        // current() returns PersistedAccount?; try? wraps it again, so flatten first.
        let existing = (try? manager.current()) ?? nil
        _currentDID = State(initialValue: existing?.did)
    }

    var body: some View {
        Group {
            if let did = currentDID {
                AuthenticatedRootView(
                    accountManager: accountManager,
                    did: did,
                    accountHandle: currentHandle,
                    accountAvatarURL: accountAvatarURL,
                    makeComposer: { parentURI in
                        ComposerViewModel(submitter: LiveComposer(accountManager: accountManager), replyParentURI: parentURI)
                    },
                    makeQuoteComposer: { post in
                        ComposerViewModel(submitter: LiveComposer(accountManager: accountManager), quotedPost: post)
                    }
                )
                .id(did)
                .task(id: currentDID) { await loadAvatar() }
            } else {
                LoginView(model: loginModel) { did in
                    currentDID = did
                }
            }
        }
        .environmentObject(themeStore)
        .environmentObject(displaySettings)
        .environmentObject(fontSettings)
        // Establish the app-wide base font and Japanese typesetting so line metrics
        // and glyph selection are correct regardless of UI locale.
        .font(.app(.body))
        .typesettingLanguage(.init(languageCode: .japanese))
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

    private let accountHandle: String
    private let accountAvatarURL: URL?
    private let makeComposer: @MainActor (String?) -> ComposerViewModel
    private let makeQuoteComposer: @MainActor (PostDisplay) -> ComposerViewModel

    init(
        accountManager: AccountManager,
        did: String,
        accountHandle: String,
        accountAvatarURL: URL?,
        makeComposer: @escaping @MainActor (String?) -> ComposerViewModel,
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
                makeFilterModel: { query in
                    TimelineViewModel(loader: LiveSearchLoader(accountManager: accountManager, query: query))
                }
            )
        )
        self.accountHandle = accountHandle
        self.accountAvatarURL = accountAvatarURL
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
            makeComposer: makeComposer,
            makeQuoteComposer: makeQuoteComposer
        )
    }
}
