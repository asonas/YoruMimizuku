import Combine
import SwiftUI
import BlueskyCore
import YoruMimizukuKit

/// The main window: a cmux-style vertical tab rail (home, notifications, filter,
/// and closable conversation tabs) on the left, with the selected tab's content
/// on the right. Home and filter tabs render a `FeedView`; Cmd-Shift-J/K cycle the
/// tabs. The lightbox, settings, and composer sheets float above everything.
struct MainWindowView: View {
    @ObservedObject var model: TimelineViewModel
    @ObservedObject var notifications: NotificationsViewModel
    @ObservedObject var workspace: WorkspaceModel
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var displaySettings: DisplaySettingsStore
    @EnvironmentObject private var fontSettings: FontSettingsStore
    @EnvironmentObject private var notificationSettings: NotificationSettingsStore
    var accountHandle: String
    var accountAvatarURL: URL?
    /// The signed-in account's DID, threaded to each feed so the viewer's own posts
    /// can offer a delete action.
    var accountDID: String
    /// All stored accounts, for the sidebar account switcher.
    var accounts: [AccountSummary]
    /// Switch the active account to the given DID.
    var onSwitchAccount: (String) -> Void
    /// Start the add-account login flow.
    var onAddAccount: () -> Void
    /// Log out of the current account.
    var onLogout: () -> Void
    /// Builds a composer VM for a new post (nil parent) or a reply (parent post).
    var makeComposer: @MainActor (PostDisplay?) -> ComposerViewModel
    /// Builds a composer VM that quotes `post`.
    var makeQuoteComposer: @MainActor (PostDisplay) -> ComposerViewModel

    @State private var lightbox: ImageGallery?
    @State private var showSettings = false
    /// The composer sheet's view model; non-nil while the sheet is open.
    @State private var composer: ComposerViewModel?

    /// The reference "now" for every relative timestamp ("32m") in the window.
    /// Driven by `clock` below so the displayed ages advance; a captured constant
    /// would freeze and the times would never update.
    @State private var now = Date()
    /// Ticks on the main run loop to refresh `now`. 15s rather than 1s: relative
    /// timestamps are minutes/hours for all but the newest posts, so a per-second
    /// tick re-rendered every visible row 15x more often than the displayed string
    /// could change. Only sub-minute ages ("30s") update in coarser steps now,
    /// which is an acceptable trade for far less render churn while scrolling.
    private let clock = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    /// How often every badge-bearing tab polls for new content, from the user's
    /// notification settings.
    private var pollInterval: Duration { notificationSettings.pollInterval }

    var body: some View {
        // A stable ZStack hosts the sheet/overlays so changing the font (which
        // re-ids the inner content to refresh every `.font(.app(...))`) never
        // dismisses the settings sheet or resets `showSettings`.
        ZStack {
            splitView
                .id("\(fontSettings.family)|\(fontSettings.baseSize)")
        }
        // Cmd-Shift-J/K cycle the sidebar tabs from anywhere in the window.
        .background { tabShortcuts }
        // Lets the File > 新規投稿 menu command (⌘N) open this window's composer.
        .focusedSceneValue(\.newPost, NewPostAction { composeFromMenu() })
        // Lets the ⌘, settings menu command open this window's settings sheet.
        .focusedSceneValue(\.openSettings, OpenSettingsAction { showSettings = true })
        .onReceive(clock) { now = $0 }
        .task {
            model.startPolling(every: pollInterval)
            notifications.startPolling(every: pollInterval)
            for tab in workspace.filters { tab.model.startPolling(every: pollInterval) }
            syncActiveTab()
        }
        .onChange(of: workspace.filters.map(\.id)) { _, _ in
            for tab in workspace.filters { tab.model.startPolling(every: pollInterval) }
        }
        .onChange(of: workspace.filters.map(\.contentKey)) { _, _ in
            for tab in workspace.filters { tab.model.startPolling(every: pollInterval) }
            syncActiveTab()
        }
        .onChange(of: workspace.selection) { _, _ in syncActiveTab() }
        // Changing the polling interval restarts every poller so the new cadence
        // takes effect immediately rather than only on the next launch.
        .onChange(of: notificationSettings.pollIntervalSeconds) { _, _ in restartPolling() }
        .overlay {
            if let lightbox {
                ImageLightboxView(gallery: lightbox) { self.lightbox = nil }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(displaySettings)
                .environmentObject(fontSettings)
                .environmentObject(notificationSettings)
        }
        .sheet(item: $composer) { model in
            ComposerView(model: model) { composer = nil }
                .environmentObject(theme)
                .environmentObject(fontSettings)
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            SidebarView(
                workspace: workspace,
                accountHandle: accountHandle,
                accountAvatarURL: accountAvatarURL,
                accountDID: accountDID,
                accounts: accounts,
                onOpenSettings: { showSettings = true },
                onSwitchAccount: onSwitchAccount,
                onAddAccount: onAddAccount,
                onLogout: onLogout,
                showsBadges: notificationSettings.showsUnreadBadges,
                homeUnread: model.unreadCount,
                notificationsUnread: notifications.unreadCount
            )
            .overlay(alignment: .trailing) {
                Rectangle().fill(theme.divider).frame(width: 1).ignoresSafeArea()
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 320)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 600, minHeight: 540)
        // Tapping a hashtag in any post body opens a filter tab for that tag
        // instead of launching the browser; all other links fall through to the
        // system handler.
        .environment(\.openURL, OpenURLAction { url in
            if let tag = RichText.hashtag(from: url) {
                workspace.openHashtagFilter(tag: tag)
                return .handled
            }
            return .systemAction
        })
    }

    @ViewBuilder
    private var detail: some View {
        switch workspace.selection {
        case .home:
            FeedView(
                model: model, title: nil, now: now,
                onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                onOpenConversation: { workspace.openConversation($0) },
                onCompose: { compose(refreshing: model) },
                onReply: { openReplyComposer($0, refreshing: model) },
                onQuote: { openQuoteComposer($0, refreshing: model) },
                onOpenAuthor: { openAuthor(for: $0) },
                onOpenQuote: { openQuotedPost($0) },
                currentDID: accountDID
            )
        case .notifications:
            NotificationsView(
                model: notifications, now: now,
                onOpenAuthor: { actor in
                    workspace.openAuthor(did: actor.handle, handle: actor.handle, displayName: actor.displayName, avatarURL: actor.avatarURL)
                },
                onOpenSubject: { group in
                    openNotificationSubject(group)
                }
            )
        case let .filter(id):
            if let tab = workspace.filter(id: id) {
                FeedView(
                    model: tab.model, title: tab.title, now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenConversation: { workspace.openConversation($0) },
                    onCompose: { compose(refreshing: tab.model) },
                    onReply: { openReplyComposer($0, refreshing: tab.model) },
                    onQuote: { openQuoteComposer($0, refreshing: tab.model) },
                    onOpenAuthor: { openAuthor(for: $0) },
                    onOpenQuote: { openQuotedPost($0) },
                    currentDID: accountDID
                )
                // Key identity on the query so editing it rebuilds the feed (and
                // restarts its load/poll task); a relabel keeps the same identity.
                .id("\(id)-\(tab.contentKey)")
            } else {
                Color.clear.background(theme.canvas)
            }
        case let .conversation(id):
            if let tab = workspace.conversation(id: id) {
                ConversationView(
                    model: tab.model,
                    now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenConversation: { workspace.openConversation($0) },
                    onOpenAuthor: { openAuthor(for: $0) },
                    onOpenQuote: { openQuotedPost($0) }
                )
                .id(id)
            } else {
                Color.clear.background(theme.canvas)
            }
        case let .author(id):
            if let tab = workspace.author(id: id) {
                AuthorView(
                    tab: tab,
                    now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenConversation: { workspace.openConversation($0) },
                    onOpenAuthor: { openAuthor(for: $0) },
                    onReply: { openReplyComposer($0, refreshing: tab.model) },
                    onQuote: { openQuoteComposer($0, refreshing: tab.model) },
                    onOpenQuote: { openQuotedPost($0) },
                    currentDID: accountDID
                )
                .id(id)
            } else {
                Color.clear.background(theme.canvas)
            }
        }
    }

    /// Open the author tab for `post`, deriving the author DID from the post URI.
    /// No-op when the URI is not a well-formed AT-URI.
    private func openAuthor(for post: PostDisplay) {
        guard let did = ATURI.repo(post.id), !did.isEmpty else { return }
        workspace.openAuthor(did: did, handle: post.authorHandle, displayName: post.authorDisplayName, avatarURL: post.avatarURL)
    }

    /// The timeline backing the currently selected tab, so a post composed from
    /// the menu refreshes the feed the user is looking at. Tabs without their
    /// own timeline (notifications / conversation / author) fall back to home.
    private var activeTimelineModel: TimelineViewModel {
        switch workspace.selection {
        case let .filter(id):
            return workspace.filter(id: id)?.model ?? model
        default:
            return model
        }
    }

    /// ⌘N from the File menu: open a new-post composer over the current tab.
    /// No-op while another sheet is already up so the command cannot stack or
    /// replace an in-progress draft.
    private func composeFromMenu() {
        guard composer == nil, !showSettings else { return }
        compose(refreshing: activeTimelineModel)
    }

    /// Open the composer for a new post; on success dismiss it and refresh the
    /// feed that was visible so the new post can surface.
    private func compose(refreshing model: TimelineViewModel) {
        let vm = makeComposer(nil)
        vm.onPosted = { composer = nil; Task { await model.refresh() } }
        composer = vm
    }

    /// Open the composer replying to `post`; on success dismiss it and refresh the
    /// feed that was visible so the reply count and any surfaced reply update.
    private func openReplyComposer(_ post: PostDisplay, refreshing model: TimelineViewModel) {
        let vm = makeComposer(post)
        vm.onPosted = { composer = nil; Task { await model.refresh() } }
        composer = vm
    }

    /// Open the composer quoting `post`; on success dismiss it and refresh the feed
    /// that was visible so the quote can surface.
    private func openQuoteComposer(_ post: PostDisplay, refreshing model: TimelineViewModel) {
        let vm = makeQuoteComposer(post)
        vm.onPosted = { composer = nil; Task { await model.refresh() } }
        composer = vm
    }

    /// Open the conversation for a tapped quote card. The quoted post arrives as
    /// a `QuotedPost` (not a full `PostDisplay`), so this uses the URI-based
    /// conversation entry point with the card's snippet as the tab label.
    private func openQuotedPost(_ quote: QuotedPost) {
        workspace.openConversation(
            anchorID: quote.id,
            title: quote.authorDisplayName,
            handle: "@\(quote.authorHandle)",
            subtitle: quote.body
        )
    }

    private func openNotificationSubject(_ group: NotificationGroup) {
        guard let uri = group.subjectURI else { return }
        let actor = group.actors.first
        let displayName = actor.map { $0.displayName.isEmpty ? $0.handle : $0.displayName } ?? "通知"
        let handle = actor.map { "@\($0.handle)" } ?? ""
        let subtitle = group.subjectText ?? group.text ?? (group.subjectImageURL == nil ? "" : "画像")
        workspace.openConversation(anchorID: uri, title: displayName, handle: handle, subtitle: subtitle)
    }

    /// Stop and restart every poller so a changed polling interval takes effect at
    /// once. Authors are handled by `syncActiveTab`, which only polls the active one.
    private func restartPolling() {
        let interval = pollInterval
        model.stopPolling(); model.startPolling(every: interval)
        notifications.stopPolling(); notifications.startPolling(every: interval)
        for tab in workspace.filters {
            tab.model.stopPolling(); tab.model.startPolling(every: interval)
        }
        syncActiveTab()
    }

    /// Mark the selected badge-bearing tab active (badge stays 0 while viewed) and
    /// the others inactive. Conversation/author tabs carry no badge and are ignored.
    private func syncActiveTab() {
        model.setActive(workspace.selection == .home)
        notifications.setActive(workspace.selection == .notifications)
        for tab in workspace.filters {
            tab.model.setActive(workspace.selection == .filter(tab.id))
        }
        for tab in workspace.authors {
            let isActive = workspace.selection == .author(tab.id)
            tab.model.setActive(isActive)
            if isActive {
                tab.model.startPolling(every: pollInterval)
            } else {
                tab.model.stopPolling()
            }
        }
    }

    // MARK: - Keyboard shortcuts

    /// Zero-size, invisible buttons whose key equivalents drive tab cycling. Hosted
    /// in a `.background` so they register window-wide without occupying layout.
    private var tabShortcuts: some View {
        ZStack {
            Button("") { workspace.selectNextTab() }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            Button("") { workspace.selectPreviousTab() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
