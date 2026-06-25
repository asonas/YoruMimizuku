import SwiftUI
import UIKit
import BlueskyCore
import PlatformApple
import YoruMimizukuKit

struct RootView: View {
    @State private var currentDID: String?
    @State private var accountAvatarURL: URL?
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
                    accountAvatarURL: accountAvatarURL
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
        .environmentObject(theme)
        .environmentObject(displaySettings)
        .onReceive(NotificationCenter.default.publisher(for: SessionExpiry.notification)) { _ in
            handleSessionExpired()
        }
    }

    private var currentHandle: String {
        let account = (try? accountManager.current()) ?? nil
        return account?.handle ?? account?.did ?? ""
    }

    private func loadAvatar() async {
        accountAvatarURL = try? await profileLoader.loadCurrentAvatar()
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

    init(accountManager: AccountManager, did: String, accountHandle: String, accountAvatarURL: URL?) {
        self.accountManager = accountManager
        self.accountHandle = accountHandle
        self.accountAvatarURL = accountAvatarURL
        self.accountDID = did
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
    let makeComposer: (String?, PostDisplay?) -> ComposerViewModel

    @Environment(\.openURL) private var openURL
    @State private var lightbox: ImageGallery?
    @State private var composer: ComposerViewModel?
    @State private var now = Date()
    @State private var searchText = ""
    private let clock = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
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
                            isSelected: workspace.selection == .filter(tab.id)
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
                            isSelected: workspace.selection == .author(tab.id)
                        ) {
                            workspace.selection = .author(tab.id)
                        }
                    }
                }

                Section {
                    HStack {
                        RemoteAvatar(url: accountAvatarURL, size: 24)
                        Text(accountHandle)
                            .font(.footnote)
                    }
                }
            }
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
        }
        .environment(\.openURL, OpenURLAction { url in
            if let tag = RichText.hashtag(from: url) {
                workspace.openHashtagFilter(tag: tag)
                return .handled
            }
            return .systemAction
        })
        .overlay {
            if let lightbox {
                ImageLightboxView(gallery: lightbox) { self.lightbox = nil }
            }
        }
        .sheet(item: $composer) { model in
            ComposerView(model: model)
        }
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
                title: "Home",
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
                }
            )
        case let .filter(id):
            if let tab = workspace.filter(id: id) {
                TimelineListView(
                    model: tab.model,
                    title: tab.title,
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
                        title: tab.title,
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

    private func addSearchFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        workspace.addFilter(name: query, terms: [FilterTerm(kind: .keyword, value: query)], combinator: .and)
        searchText = ""
    }

    private func openAuthor(did: String, handle: String, displayName: String?, avatarURL: URL?) {
        workspace.openAuthor(did: did, handle: handle, displayName: displayName ?? "", avatarURL: avatarURL)
    }

    private func copyPermalink(_ post: PostDisplay) {
        guard let url = PostPermalink.url(for: post) else { return }
        UIPasteboard.general.string = url.absoluteString
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
