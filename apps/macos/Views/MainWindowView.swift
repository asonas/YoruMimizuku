import Combine
import SwiftUI
import BlueskyCore
import YoruMimizukuKit

/// The main window, in three columns: the sidebar (home, notifications, pinned
/// feeds and lists, filters),
/// the selected timeline, and the detail pane where a conversation or author page
/// opens without replacing the timeline. Cmd-Shift-J/K cycle the sidebar. The
/// lightbox and composer sheet float above everything; settings open in their own
/// native `Settings { }` scene window (⌘,) rather than a per-window sheet
/// (`YoruMimizukuApp.swift`, `2026-07-24-apple-hig-remediation.md` S7).
struct MainWindowView: View {
    @ObservedObject var model: TimelineViewModel
    @ObservedObject var notifications: NotificationsViewModel
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var detailPane: DetailPaneModel
    @ObservedObject var savedFeeds: SavedFeedsModel
    let listMembership: ListMembershipModel
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var fontSettings: FontSettingsStore
    @EnvironmentObject private var notificationSettings: NotificationSettingsStore
    @EnvironmentObject private var unread: NotificationUnreadStore
    @State private var windowID = UUID()
    /// The pinned feed currently polling. Only the selected one polls, so pinning
    /// many feeds does not multiply requests.
    @State private var polledSavedFeed: String?
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
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
    /// Mutes an account (by DID) for the window's account.
    var muteAuthor: @MainActor (String) async throws -> Void

    @State private var lightbox: ImageGallery?
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

    /// The window's transient toast (e.g. copy-link confirmation), injected into
    /// the feed / conversation views and rendered as a bottom overlay.
    @StateObject private var toastCenter = ToastCenter()

    var body: some View {
        // A stable ZStack hosts the sheet/overlays so changing the font (which
        // re-ids the inner content to refresh every `.font(.app(...))`) never
        // dismisses the composer sheet.
        ZStack {
            splitView
                .id("\(fontSettings.family)|\(fontSettings.baseSize)")
                .environmentObject(toastCenter)
                .environment(\.listMembership, ListMembershipContext(model: listMembership, notify: { toastCenter.show($0) }))
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
        // Cmd-Shift-J/K cycle the sidebar tabs from anywhere in the window.
        .background { tabShortcuts }
        // Lets the File > 新規投稿 menu command (⌘N) open this window's composer.
        .focusedSceneValue(\.newPost, NewPostAction { composeFromMenu() })
        .focusedSceneObject(workspace)
        .focusedSceneValue(\.windowActions, WindowActions(
            reload: {
                if workspace.selection == .notifications {
                    Task { _ = await notifications.refresh() }
                } else {
                    Task { _ = await activeTimelineModel.refresh() }
                }
            },
            focusSearch: { isSearchFocused = true }
        ))
        .onAppear {
            unread.setPollingInterval(pollInterval)
            unread.open(accountDID, window: windowID)
        }
        .onDisappear {
            unread.close(accountDID, window: windowID)
            notifications.stopPolling()
            if case let .author(tab) = detailPane.current { tab.model.stopPolling() }
            if let id = polledSavedFeed { savedFeeds.timeline(for: id)?.stopPolling() }
            polledSavedFeed = nil
            workspace.search?.model.stopPolling()
        }
        .onReceive(clock) { now = $0 }
        .task {
            model.startPolling(every: pollInterval)
            notifications.startPolling(every: pollInterval)
            for tab in workspace.filters { tab.model.startPolling(every: pollInterval) }
            syncActiveTab()
            pollShownAuthor()
        }
        .task {
            await savedFeeds.load()
            workspace.savedFeeds = savedFeeds.sources
        }
        // Loads the window account's curated lists for "リストに追加".
        .task { await listMembership.refresh(actorDID: accountDID) }
        .onChange(of: savedFeeds.sources) { _, sources in workspace.savedFeeds = sources }
        // Pins change on other devices; re-read them when the app comes back to
        // the front, which also recovers from a launch while offline.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await savedFeeds.load() }
        }
        .onChange(of: workspace.filters.map(\.id)) { _, _ in
            for tab in workspace.filters { tab.model.startPolling(every: pollInterval) }
        }
        .onChange(of: workspace.filters.map(\.contentKey)) { _, _ in
            for tab in workspace.filters { tab.model.startPolling(every: pollInterval) }
            syncActiveTab()
        }
        .onChange(of: workspace.selection) { _, _ in syncActiveTab() }
        .onChange(of: detailPane.currentID) { _, _ in pollShownAuthor() }
        // Changing the polling interval restarts every poller so the new cadence
        // takes effect immediately rather than only on the next launch.
        .onChange(of: notificationSettings.pollIntervalSeconds) { _, _ in
            unread.setPollingInterval(pollInterval)
            restartPolling()
        }
        .overlay {
            if let lightbox {
                ImageLightboxView(gallery: lightbox) { self.lightbox = nil }
            }
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
                onSwitchAccount: onSwitchAccount,
                onAddAccount: onAddAccount,
                onLogout: onLogout,
                showsBadges: notificationSettings.showsUnreadBadges,
                homeUnread: model.unreadCount,
                notificationsUnread: unread.counts[accountDID] ?? 0
            )
            .overlay(alignment: .trailing) {
                Rectangle().fill(theme.divider).frame(width: 1).ignoresSafeArea()
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 320)
        } content: {
            timelineColumn
                // The max leaves room for the media rail, which needs a 680pt text
                // region (TimelineLayout.reflowThreshold) plus the avatar column.
                .navigationSplitViewColumnWidth(min: 360, ideal: 460, max: 960)
        } detail: {
            DetailPaneView(
                pane: detailPane,
                now: now,
                onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                onOpenConversation: { detailPane.openConversation($0) },
                onOpenAuthor: { openAuthor(for: $0) },
                onOpenQuote: { openQuotedPost($0) },
                onReply: { post, feed in openReplyComposer(post, refreshing: feed) },
                onQuote: { post, feed in openQuoteComposer(post, refreshing: feed) },
                onMute: { mute($0) },
                currentDID: accountDID
            )
            .navigationSplitViewColumnWidth(min: 320, ideal: 480)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 540)
        // The prototype's unified toolbar: the selected source and account on the
        // left, search and compose on the right.
        .searchable(text: $searchText, placement: .toolbar, prompt: "検索")
        .searchFocused($isSearchFocused)
        .onSubmit(of: .search) { workspace.openSearch(query: searchText) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { composeFromMenu() } label: {
                    Label("新規投稿", systemImage: "square.and.pencil")
                }
                .help("新規投稿 (⌘N)")
            }
        }
        .navigationTitle(workspace.selectionTitle)
        .navigationSubtitle(accountHandle.isEmpty ? "" : "@\(accountHandle)")
        // Tapping a hashtag opens a filter tab; tapping a mention opens the
        // author's page in the detail pane; every other link falls through to the
        // browser.
        .environment(\.openURL, OpenURLAction { url in
            if let tag = RichText.hashtag(from: url) {
                workspace.openHashtagFilter(tag: tag)
                return .handled
            }
            if let did = RichText.mentionDID(from: url) {
                // Only the identifier is available at tap time (the openURL action
                // sees a URL, not the "@handle" span text), so open by DID and let
                // the author model resolve handle / display name / avatar.
                detailPane.openAuthor(did: did, handle: "", displayName: "", avatarURL: nil)
                return .handled
            }
            return .systemAction
        })
    }

    /// The middle column: the timeline picked in the sidebar. Conversations and
    /// authors open in the detail pane, so on macOS the selection never points at
    /// a conversation or author tab (those remain for iPadOS).
    @ViewBuilder
    private var timelineColumn: some View {
        switch workspace.selection {
        case .home:
            FeedView(
                model: model, title: WorkspaceModel.homeTitle, now: now,
                onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                onOpenConversation: { detailPane.openConversation($0) },
                onCompose: { compose(refreshing: model) },
                onReply: { openReplyComposer($0, refreshing: model) },
                onQuote: { openQuoteComposer($0, refreshing: model) },
                onOpenAuthor: { openAuthor(for: $0) },
                onOpenQuote: { openQuotedPost($0) },
                currentDID: accountDID,
                onMute: { mute($0) }
            )
        case .notifications:
            NotificationsView(
                model: notifications, now: now,
                onOpenAuthor: { actor in
                    detailPane.openAuthor(did: actor.handle, handle: actor.handle, displayName: actor.displayName, avatarURL: actor.avatarURL)
                },
                onOpenSubject: { group in
                    openNotificationSubject(group)
                },
                onDisplayUnread: { date in
                    Task { await unread.markDisplayed(accountDID, through: date) }
                }
            )
        case let .filter(id):
            if let tab = workspace.filter(id: id) {
                FeedView(
                    model: tab.model, title: tab.title, now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenConversation: { detailPane.openConversation($0) },
                    onCompose: { compose(refreshing: tab.model) },
                    onReply: { openReplyComposer($0, refreshing: tab.model) },
                    onQuote: { openQuoteComposer($0, refreshing: tab.model) },
                    onOpenAuthor: { openAuthor(for: $0) },
                    onOpenQuote: { openQuotedPost($0) },
                    currentDID: accountDID,
                    onMute: { mute($0) }
                )
                // Key identity on the query so editing it rebuilds the feed (and
                // restarts its load/poll task); a relabel keeps the same identity.
                .id("\(id)-\(tab.contentKey)")
            } else {
                Color.clear.background(theme.canvas)
            }
        case let .savedFeed(id):
            if let source = savedFeeds.source(id: id), let timeline = savedFeeds.timeline(for: id) {
                FeedView(
                    model: timeline, title: source.title, now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenConversation: { detailPane.openConversation($0) },
                    onCompose: { compose(refreshing: timeline) },
                    onReply: { openReplyComposer($0, refreshing: timeline) },
                    onQuote: { openQuoteComposer($0, refreshing: timeline) },
                    onOpenAuthor: { openAuthor(for: $0) },
                    onOpenQuote: { openQuotedPost($0) },
                    currentDID: accountDID,
                    onMute: { mute($0) },
                    headerAccessory: AnyView(SavedFeedInfoButton(source: source))
                )
                .id(id)
            } else {
                Color.clear.background(theme.canvas)
            }
        case .search:
            if let search = workspace.search {
                FeedView(
                    model: search.model, title: "検索: \(search.query)", now: now,
                    onImageTap: { urls, index in lightbox = ImageGallery(urls: urls, index: index) },
                    onOpenConversation: { detailPane.openConversation($0) },
                    onCompose: { compose(refreshing: search.model) },
                    onReply: { openReplyComposer($0, refreshing: search.model) },
                    onQuote: { openQuoteComposer($0, refreshing: search.model) },
                    onOpenAuthor: { openAuthor(for: $0) },
                    onOpenQuote: { openQuotedPost($0) },
                    currentDID: accountDID,
                    onMute: { mute($0) },
                    headerAccessory: AnyView(
                        Button("フィルターとして保存") { workspace.saveSearchAsFilter() }
                            .buttonStyle(.borderless)
                            .help("この検索をサイドバーのフィルターに残す")
                    )
                )
                // Keyed on the model, not the query: submitting the same query
                // again replaces the model and must load it.
                .id(ObjectIdentifier(search.model))
                .task(id: ObjectIdentifier(search.model)) { search.model.startPolling(every: pollInterval) }
            } else {
                Color.clear.background(theme.canvas)
            }
        case .conversation, .author:
            Color.clear.background(theme.canvas)
        }
    }

    /// Mute `post`'s author for the window's account, then drop their posts from
    /// every timeline in the window.
    private func mute(_ post: PostDisplay) {
        guard let did = ATURI.repo(post.id) else { return }
        Task {
            do {
                try await muteAuthor(did)
                model.removePosts(byAuthor: did)
                for tab in workspace.filters { tab.model.removePosts(byAuthor: did) }
                for source in savedFeeds.sources { savedFeeds.timeline(for: source.id)?.removePosts(byAuthor: did) }
                workspace.search?.model.removePosts(byAuthor: did)
                if case let .author(tab) = detailPane.current { tab.model.removePosts(byAuthor: did) }
                toastCenter.show("@\(post.authorHandle) をミュートしました")
            } catch {
                toastCenter.show("ミュートできませんでした")
            }
        }
    }

    /// Open the author page for `post`, deriving the author DID from the post URI.
    /// No-op when the URI is not a well-formed AT-URI.
    private func openAuthor(for post: PostDisplay) {
        guard let did = ATURI.repo(post.id), !did.isEmpty else { return }
        detailPane.openAuthor(did: did, handle: post.authorHandle, displayName: post.authorDisplayName, avatarURL: post.avatarURL)
    }

    /// The timeline backing the currently selected tab, so a post composed from
    /// the menu refreshes the feed the user is looking at. Tabs without their
    /// own timeline (notifications / conversation / author) fall back to home.
    private var activeTimelineModel: TimelineViewModel {
        switch workspace.selection {
        case let .filter(id):
            return workspace.filter(id: id)?.model ?? model
        case let .savedFeed(id):
            return savedFeeds.timeline(for: id) ?? model
        case .search:
            return workspace.search?.model ?? model
        default:
            return model
        }
    }

    /// ⌘N from the File menu: open a new-post composer over the current tab.
    /// No-op while the composer is already open so the command cannot stack or
    /// replace an in-progress draft. (Settings now lives in its own window, so
    /// it can no longer conflict with the composer sheet.)
    private func composeFromMenu() {
        guard composer == nil else { return }
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
        // ⌘↩ (reply) is also the composer's send key; never replace an open draft.
        guard composer == nil else { return }
        let vm = makeComposer(post)
        vm.onPosted = { composer = nil; Task { await model.refresh() } }
        composer = vm
    }

    /// Open the composer quoting `post`; on success dismiss it and refresh the feed
    /// that was visible so the quote can surface.
    private func openQuoteComposer(_ post: PostDisplay, refreshing model: TimelineViewModel) {
        guard composer == nil else { return }
        let vm = makeQuoteComposer(post)
        vm.onPosted = { composer = nil; Task { await model.refresh() } }
        composer = vm
    }

    /// Open the conversation for a tapped quote card. The quoted post arrives as
    /// a `QuotedPost` (not a full `PostDisplay`), so this uses the URI-based
    /// conversation entry point with the card's snippet as the tab label.
    private func openQuotedPost(_ quote: QuotedPost) {
        detailPane.openConversation(
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
        detailPane.openConversation(anchorID: uri, title: displayName, handle: handle, subtitle: subtitle)
    }

    /// Stop and restart every poller so a changed polling interval takes effect at
    /// once, including the author page shown in the detail pane.
    private func restartPolling() {
        let interval = pollInterval
        model.stopPolling(); model.startPolling(every: interval)
        notifications.stopPolling(); notifications.startPolling(every: interval)
        for tab in workspace.filters {
            tab.model.stopPolling(); tab.model.startPolling(every: interval)
        }
        if case let .author(tab) = detailPane.current { tab.model.stopPolling() }
        if let id = polledSavedFeed { savedFeeds.timeline(for: id)?.stopPolling() }
        polledSavedFeed = nil
        if let search = workspace.search {
            search.model.stopPolling(); search.model.startPolling(every: interval)
        }
        syncActiveTab()
        pollShownAuthor()
    }

    /// Mark the selected badge-bearing tab active (badge stays 0 while viewed) and
    /// the others inactive.
    private func syncActiveTab() {
        model.setActive(workspace.selection == .home)
        for tab in workspace.filters {
            tab.model.setActive(workspace.selection == .filter(tab.id))
        }
        pollSelectedSavedFeed()
    }

    /// Poll only the selected pinned feed; stop the one left behind.
    private func pollSelectedSavedFeed() {
        let selected: String? = if case let .savedFeed(id) = workspace.selection { id } else { nil }
        guard selected != polledSavedFeed else { return }
        if let previous = polledSavedFeed { savedFeeds.timeline(for: previous)?.stopPolling() }
        polledSavedFeed = selected
        if let selected, let timeline = savedFeeds.timeline(for: selected) {
            timeline.setActive(true)
            timeline.startPolling(every: pollInterval)
        }
    }

    /// Poll the author page shown in the detail pane. `DetailPaneModel` stops the
    /// feed of any author page it leaves.
    private func pollShownAuthor() {
        guard case let .author(tab) = detailPane.current else { return }
        tab.model.setActive(true)
        tab.model.startPolling(every: pollInterval)
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
