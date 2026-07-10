import SwiftUI
import UIKit
import BlueskyCore
import PlatformApple
import YoruMimizukuKit

struct RootView: View {
    @State private var currentDID: String?
    @State private var accountAvatarURL: URL?
    /// Drives the "add account" login sheet shown over the signed-in UI.
    @State private var isAddingAccount = false
    @StateObject private var loginModel: LoginViewModel
    /// Shared look (palette) and timeline density, injected into the whole scene so
    /// every view reads the same themed colors and `.app(...)` fonts as macOS.
    @StateObject private var theme = ThemeStore()
    @StateObject private var displaySettings = DisplaySettingsStore()

    private let accountManager: AccountManager
    private let profileLoader: LiveProfileLoader

    init() {
        let storage = KeychainStorage(service: "as.ason.YoruMimizukuPad")
        let manager = AccountManager(store: AccountStore(storage: storage))
        self.accountManager = manager
        self.profileLoader = LiveProfileLoader(accountManager: manager)
        _loginModel = StateObject(wrappedValue: LoginViewModel(performer: LiveLoginPerformer(accountManager: manager)))
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
                    accounts: accounts,
                    onSwitchAccount: { switchAccount(to: $0) },
                    onAddAccount: { startAddAccount() },
                    onLogout: { logout() }
                )
                .id(did)
                .task(id: currentDID) { await loadAvatar() }
            } else {
                LoginView(model: loginModel) { did in
                    currentDID = did
                }
            }
        }
        .background(theme.canvas)
        .preferredColorScheme(theme.preferredColorScheme)
        .environmentObject(theme)
        .environmentObject(displaySettings)
        .onReceive(NotificationCenter.default.publisher(for: SessionExpiry.notification)) { _ in
            handleSessionExpired()
        }
        // The "add account" login flow, presented over the signed-in UI. On success
        // the new account is current (AccountManager.add sets it), so adopting its
        // DID rebuilds the authenticated subtree for the new account.
        .sheet(isPresented: $isAddingAccount) {
            LoginView(model: loginModel) { did in
                isAddingAccount = false
                currentDID = did
            }
            .environmentObject(theme)
            .environmentObject(displaySettings)
        }
    }

    private var currentHandle: String {
        let account = (try? accountManager.current()) ?? nil
        return account?.handle ?? account?.did ?? ""
    }

    /// The stored accounts for the switcher menu. Empty if the read fails.
    private var accounts: [AccountSummary] {
        (try? accountManager.summaries()) ?? []
    }

    private func loadAvatar() async {
        accountAvatarURL = try? await profileLoader.loadCurrentAvatar()
    }

    /// Switch the active account to `did` and rebuild the signed-in subtree for it.
    private func switchAccount(to did: String) {
        guard did != currentDID else { return }
        try? accountManager.switchTo(did: did)
        accountAvatarURL = nil
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
        accountAvatarURL = nil
        currentDID = (try? accountManager.removeAndAdvance(did: did)) ?? nil
    }

    private func handleSessionExpired() {
        guard let did = currentDID else { return }
        try? accountManager.remove(did: did)
        let remaining = (try? accountManager.allDIDs()) ?? []
        if let next = remaining.first {
            try? accountManager.switchTo(did: next)
            currentDID = next
        } else {
            currentDID = nil
        }
    }
}

private struct AuthenticatedRootView: View {
    @StateObject private var timelineModel: TimelineViewModel
    @StateObject private var notificationsModel: NotificationsViewModel
    @StateObject private var workspace: WorkspaceModel

    private let accountHandle: String
    private let accountAvatarURL: URL?
    private let accountManager: AccountManager
    private let accountDID: String
    private let accounts: [AccountSummary]
    private let onSwitchAccount: (String) -> Void
    private let onAddAccount: () -> Void
    private let onLogout: () -> Void

    init(
        accountManager: AccountManager,
        did: String,
        accountHandle: String,
        accountAvatarURL: URL?,
        accounts: [AccountSummary],
        onSwitchAccount: @escaping (String) -> Void,
        onAddAccount: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) {
        self.accountManager = accountManager
        self.accountHandle = accountHandle
        self.accountAvatarURL = accountAvatarURL
        self.accountDID = did
        self.accounts = accounts
        self.onSwitchAccount = onSwitchAccount
        self.onAddAccount = onAddAccount
        self.onLogout = onLogout
        _timelineModel = StateObject(
            wrappedValue: TimelineViewModel(
                loader: LiveTimelineLoader(accountManager: accountManager),
                interactor: LivePostInteractor(accountManager: accountManager)
            )
        )
        _notificationsModel = StateObject(
            wrappedValue: NotificationsViewModel(loader: LiveNotificationsLoader(accountManager: accountManager))
        )
        _workspace = StateObject(
            wrappedValue: WorkspaceModel(
                filterStore: SavedFilterStore(port: FilterFileStore(did: did)),
                persistence: UserDefaultsConversationStore(key: "workspace.conversations.v1.\(did)"),
                makeThreadModel: { uri in
                    ThreadViewModel(
                        loader: LiveThreadLoader(accountManager: accountManager),
                        uri: uri,
                        interactor: LivePostInteractor(accountManager: accountManager)
                    )
                },
                makeFilterModel: { filter in
                    TimelineViewModel(
                        loader: LiveSearchLoader(accountManager: accountManager, subqueries: filter.subqueries),
                        interactor: LivePostInteractor(accountManager: accountManager)
                    )
                },
                makeAuthorModel: { did in
                    TimelineViewModel(
                        loader: LiveAuthorFeedLoader(accountManager: accountManager, actor: did),
                        interactor: LivePostInteractor(accountManager: accountManager)
                    )
                },
                makeAuthorHeader: { did, initial in
                    ProfileHeaderViewModel(
                        loader: LiveAuthorProfileLoader(accountManager: accountManager),
                        actor: did,
                        initial: initial
                    )
                }
            )
        )
    }

    var body: some View {
        MainShellView(
            timelineModel: timelineModel,
            notificationsModel: notificationsModel,
            workspace: workspace,
            accountHandle: accountHandle,
            accountAvatarURL: accountAvatarURL,
            accountDID: accountDID,
            accounts: accounts,
            onSwitchAccount: onSwitchAccount,
            onAddAccount: onAddAccount,
            onLogout: onLogout,
            makeComposer: { parentURI, quotedPost in
                ComposerViewModel(
                    submitter: LiveComposer(accountManager: accountManager),
                    replyParentURI: parentURI,
                    quotedPost: quotedPost
                )
            }
        )
    }
}

private struct MainShellView: View {
    @ObservedObject var timelineModel: TimelineViewModel
    @ObservedObject var notificationsModel: NotificationsViewModel
    @ObservedObject var workspace: WorkspaceModel
    let accountHandle: String
    let accountAvatarURL: URL?
    let accountDID: String
    let accounts: [AccountSummary]
    let onSwitchAccount: (String) -> Void
    let onAddAccount: () -> Void
    let onLogout: () -> Void
    let makeComposer: (String?, PostDisplay?) -> ComposerViewModel

    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.openURL) private var openURL
    /// The scene's transient toast (e.g. copy-link confirmation), rendered as a
    /// bottom overlay. `copyPermalink` lives here in `MainShellView`, so no
    /// env-object plumbing into child views is needed (unlike macOS).
    @StateObject private var toastCenter = ToastCenter()
    @State private var lightbox: ImageGallery?
    @State private var composer: ComposerViewModel?
    @State private var now = Date()
    @State private var searchText = ""
    // Pin the sidebar visible. The detail pane hides its navigation bar for a
    // chromeless canvas (no empty title band), which also removes the toggle that
    // would otherwise reveal the sidebar — so keep both columns shown, like macOS.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private let clock = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    #if DEBUG
    /// Opens the DEBUG-only design catalog. The iPad app has no settings screen
    /// yet, so this hangs off the sidebar instead — see
    /// `docs/superpowers/specs/2026-07-03-design-catalog-design.md`.
    @State private var showsCatalog = false
    #endif

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section {
                    SidebarButton(title: "Home", systemImage: "house", isSelected: workspace.selection == .home) {
                        workspace.selection = .home
                    }
                    SidebarButton(
                        title: "Notifications",
                        systemImage: "bell",
                        badge: notificationsModel.unreadCount,
                        isSelected: workspace.selection == .notifications
                    ) {
                        workspace.selection = .notifications
                    }
                }

                Section("Filters") {
                    HStack {
                        TextField("検索語", text: $searchText)
                            .textInputAutocapitalization(.never)
                        Button {
                            addSearchFilter()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ForEach(workspace.filters) { tab in
                        SidebarButton(
                            title: tab.title,
                            systemImage: "magnifyingglass",
                            badge: tab.model.unreadCount,
                            isSelected: workspace.selection == .filter(tab.id),
                            onClose: { workspace.removeFilter(id: tab.id) }
                        ) {
                            workspace.selection = .filter(tab.id)
                        }
                    }
                }

                Section("Conversations") {
                    ForEach(workspace.conversations) { tab in
                        SidebarButton(
                            title: tab.title,
                            systemImage: "bubble.left.and.bubble.right",
                            isSelected: workspace.selection == .conversation(tab.id),
                            // iPad has no hover, so the close affordance is an always-visible
                            // trailing button rather than the macOS hover-reveal one.
                            // closeConversation re-selects an adjacent tab or falls back to home.
                            onClose: { workspace.closeConversation(tab.id) }
                        ) {
                            workspace.selection = .conversation(tab.id)
                        }
                    }
                }

                Section("Authors") {
                    ForEach(workspace.authors) { tab in
                        SidebarButton(
                            title: tab.title,
                            systemImage: "person",
                            isSelected: workspace.selection == .author(tab.id),
                            onClose: { workspace.closeAuthor(tab.id) }
                        ) {
                            workspace.selection = .author(tab.id)
                        }
                    }
                }

                #if DEBUG
                Section {
                    Button {
                        showsCatalog = true
                    } label: {
                        Label("デザインカタログ", systemImage: "square.grid.2x2")
                    }
                }
                #endif

                Section {
                    accountMenu
                }
            }
            .scrollContentBackground(.hidden)
            .background { theme.canvas }
            .navigationTitle("YoruMimizuku")
            .toolbar {
                Button {
                    composer = makeComposer(nil, nil)
                } label: {
                    Label("投稿", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: [])
            }
        } detail: {
            detail
                // The detail views set no title, so the inline navigation bar
                // would render as an empty band above the timeline/notifications
                // canvas. Hide it so the themed canvas runs to the top edge.
                .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.openURL, OpenURLAction { url in
            if let tag = RichText.hashtag(from: url) {
                workspace.openHashtagFilter(tag: tag)
                return .handled
            }
            if let did = RichText.mentionDID(from: url) {
                // Only the identifier is available at tap time (the openURL action
                // sees a URL, not the "@handle" span text), so open by DID and let
                // the author model resolve handle / display name / avatar.
                workspace.openAuthor(did: did, handle: "", displayName: "", avatarURL: nil)
                return .handled
            }
            return .systemAction
        })
        .overlay {
            if let lightbox {
                ImageLightboxView(gallery: lightbox) { self.lightbox = nil }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = toastCenter.current {
                ToastView(message: toast)
                    .padding(.bottom, 24)
                    .onTapGesture { toastCenter.dismiss() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastCenter.current)
        .sheet(item: $composer) { model in
            ComposerView(model: model)
        }
        #if DEBUG
        .sheet(isPresented: $showsCatalog) {
            DesignCatalogView()
        }
        #endif
        .onReceive(clock) { now = $0 }
        .task {
            timelineModel.startPolling(every: .seconds(30))
            notificationsModel.startPolling(every: .seconds(30))
            syncActiveTab()
        }
        .onChange(of: workspace.selection) { _, _ in syncActiveTab() }
        .onDisappear {
            timelineModel.stopPolling()
            notificationsModel.stopPolling()
            workspace.filters.forEach { $0.model.stopPolling() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch workspace.selection {
        case .home:
            TimelineListView(
                model: timelineModel,
                now: now,
                currentDID: accountDID,
                onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                onOpenThread: workspace.openConversation,
                onOpenAuthor: openAuthor,
                onReply: { post in composer = makeComposer(post.id, nil) },
                onQuote: { post in composer = makeComposer(nil, post) },
                onCopyPermalink: copyPermalink,
                onOpenPermalink: openPermalink
            )
        case .notifications:
            NotificationsListView(
                model: notificationsModel,
                now: now,
                onOpenAuthor: { actor in
                    workspace.openAuthor(
                        did: actor.handle,
                        handle: actor.handle,
                        displayName: actor.displayName,
                        avatarURL: actor.avatarURL
                    )
                },
                onOpenSubject: openNotificationSubject
            )
        case let .filter(id):
            if let tab = workspace.filter(id: id) {
                TimelineListView(
                    model: tab.model,
                    now: now,
                    currentDID: accountDID,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenThread: workspace.openConversation,
                    onOpenAuthor: openAuthor,
                    onReply: { post in composer = makeComposer(post.id, nil) },
                    onQuote: { post in composer = makeComposer(nil, post) },
                    onCopyPermalink: copyPermalink,
                    onOpenPermalink: openPermalink
                )
            } else {
                ContentUnavailableView("Filter not found", systemImage: "magnifyingglass")
            }
        case let .conversation(id):
            if let tab = workspace.conversation(id: id) {
                ConversationView(
                    model: tab.model,
                    now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenThread: workspace.openConversation,
                    onOpenAuthor: openAuthor,
                    onReply: { post in composer = makeComposer(post.id, nil) },
                    onQuote: { post in composer = makeComposer(nil, post) },
                    onCopyPermalink: copyPermalink,
                    onOpenPermalink: openPermalink
                )
            } else {
                ContentUnavailableView("Conversation not found", systemImage: "bubble.left.and.bubble.right")
            }
        case let .author(id):
            if let tab = workspace.author(id: id) {
                VStack(spacing: 0) {
                    AuthorHeaderView(tab: tab)
                    TimelineListView(
                        model: tab.model,
                        now: now,
                        currentDID: accountDID,
                        onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                        onOpenThread: workspace.openConversation,
                        onOpenAuthor: openAuthor,
                        onReply: { post in composer = makeComposer(post.id, nil) },
                        onQuote: { post in composer = makeComposer(nil, post) },
                        onCopyPermalink: copyPermalink,
                        onOpenPermalink: openPermalink
                    )
                }
            } else {
                ContentUnavailableView("Author not found", systemImage: "person")
            }
        }
    }

    /// The bottom-of-sidebar account control: shows the current handle and, on tap,
    /// a menu to switch between stored accounts, add another, or log out. iPad has no
    /// menu bar, so this mirrors the macOS sidebar account switcher.
    private var accountMenu: some View {
        Menu {
            Section("アカウント") {
                ForEach(accounts, id: \.did) { account in
                    Button {
                        onSwitchAccount(account.did)
                    } label: {
                        if account.did == accountDID {
                            Label(accountLabel(account), systemImage: "checkmark")
                        } else {
                            Text(accountLabel(account))
                        }
                    }
                }
            }
            Divider()
            Button {
                onAddAccount()
            } label: {
                Label("アカウントを追加…", systemImage: "person.badge.plus")
            }
            Button(role: .destructive) {
                onLogout()
            } label: {
                Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            HStack(spacing: 8) {
                RemoteAvatar(url: accountAvatarURL, size: 24)
                Text("@\(accountHandle)")
                    .font(.footnote)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The display string for one account row: its handle, or its DID when missing.
    private func accountLabel(_ account: AccountSummary) -> String {
        if let handle = account.handle, !handle.isEmpty { return "@\(handle)" }
        return account.did
    }

    private func addSearchFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        workspace.addFilter(name: query, terms: [FilterTerm(kind: .keyword, value: query)], combinator: .and)
        searchText = ""
    }

    private func openAuthor(did: String, handle: String, displayName: String?, avatarURL: URL?) {
        workspace.openAuthor(did: did, handle: handle, displayName: displayName ?? "", avatarURL: avatarURL)
    }

    /// Open the post a like/repost notification is about as a conversation tab.
    private func openNotificationSubject(_ group: NotificationGroup) {
        guard let uri = group.subjectURI else { return }
        let actor = group.actors.first
        let displayName = actor.map { $0.displayName.isEmpty ? $0.handle : $0.displayName } ?? "通知"
        let handle = actor.map { "@\($0.handle)" } ?? ""
        let subtitle = group.subjectText ?? group.text ?? (group.subjectImageURL == nil ? "" : "画像")
        workspace.openConversation(anchorID: uri, title: displayName, handle: handle, subtitle: subtitle)
    }

    private func copyPermalink(_ post: PostDisplay) {
        guard let url = PostPermalink.url(for: post) else { return }
        UIPasteboard.general.string = url.absoluteString
        toastCenter.show("リンクをコピーしました")
    }

    private func openPermalink(_ post: PostDisplay) {
        guard let url = PostPermalink.url(for: post) else { return }
        openURL(url)
    }

    private func syncActiveTab() {
        timelineModel.setActive(workspace.selection == .home)
        notificationsModel.setActive(workspace.selection == .notifications)
        workspace.filters.forEach { $0.model.setActive(workspace.selection == .filter($0.id)) }
    }
}

private struct AuthorHeaderView: View {
    let tab: AuthorTab

    var body: some View {
        HStack(spacing: 14) {
            RemoteAvatar(url: tab.header.profile?.avatarURL ?? tab.avatarURL, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.header.profile?.displayName ?? tab.title)
                    .font(.title3.bold())
                Text("@\(tab.header.profile?.handle ?? tab.handle)")
                    .foregroundStyle(.secondary)
                if let bio = tab.header.profile?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.callout)
                }
            }
            Spacer()
        }
        .padding()
        .task { await tab.header.load() }
    }
}

private struct SidebarButton: View {
    let title: String
    let systemImage: String
    var badge = 0
    let isSelected: Bool
    /// When set, an always-visible trailing close button is shown (e.g. to close a
    /// conversation tab). iPad has no hover, so it cannot be a hover-reveal control.
    var onClose: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue))
                        .foregroundStyle(.white)
                }
                // Reserve trailing space so the row label never slides under the
                // overlaid close button.
                if onClose != nil { Color.clear.frame(width: 22, height: 22) }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The close button is layered in front of the row button (not nested in its
        // gesture), so tapping it closes the tab without also selecting the row.
        .overlay(alignment: .trailing) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("会話を閉じる")
            }
        }
        .listRowBackground(isSelected ? Color.blue.opacity(0.12) : Color.clear)
    }
}
