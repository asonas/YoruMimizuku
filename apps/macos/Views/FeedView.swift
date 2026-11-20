import SwiftUI
import AppKit
import BlueskyCore
import YoruMimizukuKit

/// A scrollable post feed backed by a `TimelineViewModel`. Reused by the home tab
/// and every filter tab: it loads on appear, refreshes on an interval while
/// visible, appends older posts on scroll, and supports j/k focus movement.
/// Owning its own `focusedPostID` keeps each tab's focus independent.
struct FeedView: View {
    @ObservedObject var model: TimelineViewModel
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var displaySettings: DisplaySettingsStore
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.listMembership) private var listMembership

    /// Shown in the header. Home passes nil (the sidebar already names the pane);
    /// filter tabs pass the filter name.
    var title: String?
    var showsHeader: Bool = true
    let now: Date
    var onImageTap: ([URL], Int) -> Void
    var onOpenConversation: (PostDisplay) -> Void
    /// Optional n-key new-post handler; when nil the shortcut is omitted.
    var onCompose: (() -> Void)? = nil
    /// Opens the reply composer for the tapped post.
    var onReply: (PostDisplay) -> Void = { _ in }
    /// Opens the quote composer for a post (from the repost menu).
    var onQuote: (PostDisplay) -> Void = { _ in }
    /// Opens the author tab for a tapped avatar.
    var onOpenAuthor: (PostDisplay) -> Void = { _ in }
    /// Opens the conversation of a tapped quote card's quoted post.
    var onOpenQuote: (QuotedPost) -> Void = { _ in }
    /// The signed-in account's DID. Rows whose author DID matches gain a "削除"
    /// context-menu action. Nil disables delete everywhere (e.g. previews).
    var currentDID: String? = nil
    /// Mutes the post's author ("この人をミュート").
    var onMute: (PostDisplay) -> Void = { _ in }
    /// The j/k/l/o/n keys are plain window-wide shortcuts, so only the timeline
    /// column registers them; a feed embedded in the detail pane (an author page)
    /// turns them off to avoid a second binding for the same keys.
    var registersKeyboardShortcuts: Bool = true
    /// Extra controls at the right end of the header (e.g. a pinned feed's info).
    var headerAccessory: AnyView? = nil

    @State private var focusedPostID: String?
    /// Bumped on every j/k move to scroll the focused post into view. Only keyboard
    /// navigation increments it; a click sets `focusedPostID` (for the highlight)
    /// without touching it, so tapping a post focuses it in place rather than
    /// yanking the feed. A counter (not the id) guarantees the scroll fires even
    /// when navigation lands back on a post a click had already focused.
    @State private var scrollTick = 0
    /// The own-post the viewer asked to delete, pending confirmation. Set by a
    /// row's context menu; cleared when the dialog is dismissed or the delete runs.
    @State private var pendingDelete: PostDisplay?
    /// Row ids currently laid out on screen, gathered from each row's
    /// appear/disappear. Their top-most (in display order) is the scroll anchor.
    /// A reference type mutated in place so recording the anchor on every scroll
    /// crossing never invalidates the body — the same per-scroll churn the
    /// `.equatable()` rows and the non-`@Published` `scrollAnchorID` avoid. Held in
    /// `@State` so it is recreated empty each time the tab (and thus this view) is.
    @State private var visibleRows = VisibleRows()
    /// Guards the one-shot scroll restore. The `FeedView` is torn down and rebuilt
    /// on every tab switch, so this starts false again each time the tab is shown;
    /// restore runs once, then live scroll tracking takes over.
    @State private var hasRestored = false

    /// Mutable set of on-screen row ids. A class (not a `@State Set`) so inserting
    /// or removing an id does not trigger a view update.
    private final class VisibleRows { var ids: Set<String> = [] }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader, let title {
                DetailHeader(title) { headerAccessory }
            }
            timeline
        }
        .background(theme.canvas)
        .background { if registersKeyboardShortcuts { postNavShortcuts } }
        .onChange(of: model.state) { _, _ in
            guard registersKeyboardShortcuts, focusedPostID == nil else { return }
            focusedPostID = FeedThreading.arrange(model.posts).first?.id
        }
        .focusedSceneValue(\.postActions, registersKeyboardShortcuts ? focusedPost.map(actions(for:)) : nil)
        // A post arriving while the top is still on screen fires no new onAppear,
        // so check the head again whenever the count grows.
        .onChange(of: model.newArrivals) { _, count in
            if count > 0 { recordScrollAnchor() }
        }
        // As in the prototype, the detail pane follows the selection: once j/k
        // (or the first load) rests on a post, open it there.
        .task(id: focusedPostID) {
            guard registersKeyboardShortcuts, let post = focusedPost else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            onOpenConversation(post)
        }
        // Prefetch the focused author's list membership for the right-click
        // "リストに追加" checks, once focus has rested on the post for a moment.
        .task(id: focusedPostID) {
            guard let listMembership, let id = focusedPostID, let authorDID = ATURI.repo(id) else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await listMembership.model.refreshIfStale(actorDID: authorDID)
        }
        .confirmationDialog(
            "この投稿を削除しますか？",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { post in
            Button("削除", role: .destructive) {
                pendingDelete = nil
                Task { await model.deletePost(post) }
            }
            Button("キャンセル", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("削除した投稿は元に戻せません。")
        }
    }

    /// Whether `post` is one of the signed-in account's own posts: its author DID
    /// (the repo authority in the post URI) equals `currentDID`. Only own posts may
    /// be deleted.
    private func isOwnPost(_ post: PostDisplay) -> Bool {
        guard let currentDID, let repo = ATURI.repo(post.id) else { return false }
        return repo == currentDID
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                newPostsBar(proxy)
                Group {
                    switch model.state {
                    case .idle, .loading:
                        ScrollView { loadingState }
                    case let .failed(failure):
                        ScrollView { failedState(failure) }
                    case let .loaded(posts):
                        if posts.isEmpty {
                            ScrollView { emptyState }
                        } else {
                            postList(posts, proxy: proxy)
                        }
                    }
                }
            }
            .onChange(of: scrollTick) { _, _ in
                guard let id = focusedPostID else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    /// Restore the saved scroll position once, when the recreated list first lays
    /// out. Driven from `onGeometryChange` rather than `onAppear` because a
    /// `scrollTo` issued before the list has laid out silently no-ops; a geometry
    /// callback fires after layout. Runs at most once per `FeedView` lifetime, and
    /// only unlocks live anchor tracking afterward so the initial top-down layout
    /// (rows a, b, c appearing first) cannot overwrite the saved anchor before we
    /// scroll to it.
    private func restoreScrollIfNeeded(_ proxy: ScrollViewProxy) {
        guard !hasRestored else { return }
        hasRestored = true
        guard let id = model.scrollAnchorID else { return }
        proxy.scrollTo(id, anchor: .top)
        // The pre-restore top-down layout registered the first rows (a, b, c…) as
        // visible; drop them so the onAppears fired by the jump rebuild the set from
        // the actual restored viewport instead of leaving stale top rows to win the
        // next `topVisibleID`.
        visibleRows.ids.removeAll()
    }

    /// The prototype's "新着 n 件" bar: shown while posts arrived above what the
    /// viewer last saw at the top (`TimelineViewModel.newArrivals`); clicking
    /// scrolls up to them.
    @ViewBuilder
    private func newPostsBar(_ proxy: ScrollViewProxy) -> some View {
        let count = model.newArrivals
        if count > 0 {
            Button {
                if let first = FeedThreading.arrange(model.posts).first?.id {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(first, anchor: .top) }
                }
                model.markHeadSeen()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold))
                    Text("新着 \(count) 件").font(.appSize(12, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.accentTint)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.divider).frame(height: 1) }
        }
    }

    /// Record the top-most visible row as the scroll anchor. Called only from row
    /// `onAppear` (never `onDisappear`): a tab switch tears the list down with a
    /// burst of `onDisappear`s, and recomputing there would rewrite the anchor from
    /// a draining set — down to `nil` once empty — corrupting the value the very
    /// moment it is needed. No-op until the one-shot restore has run, so the saved
    /// anchor survives the rebuild; and never overwrites a good anchor with `nil`.
    private func recordScrollAnchor() {
        guard hasRestored else { return }
        let order = FeedThreading.arrange(model.posts).map(\.id)
        if let top = FeedScrollAnchor.topVisibleID(order: order, visible: visibleRows.ids) {
            model.scrollAnchorID = top
        }
        if model.newArrivals > 0, let head = order.first, visibleRows.ids.contains(head) {
            model.markHeadSeen()
        }
    }

    /// The loaded feed. Uses `List` rather than `ScrollView { LazyVStack }`: with a
    /// LazyVStack, rows whose height was first estimated (before the row was actually
    /// measured) keep that stale slot height until a full re-layout — a normal body
    /// re-render (e.g. the per-second `now` tick) does not revisit it — leaving a
    /// blank gap below the row that only collapses on scroll or scene-phase change.
    /// `List` measures variable row heights correctly and recycles rows, so the gap
    /// never appears and memory stays bounded.
    private func postList(_ posts: [PostDisplay], proxy: ScrollViewProxy) -> some View {
        // Same-thread posts are regrouped the way Bluesky's web feed shows them
        // (oldest first within the block, connector line, no divider inside).
        let items = FeedThreading.arrange(posts)
        // Each row's predecessor, so a separator can hide next to the selection.
        let previousByID = Dictionary(
            zip(items.dropFirst().map(\.id), items.map(\.id)), uniquingKeysWith: { first, _ in first }
        )
        return List {
            ForEach(items) { item in
                let post = item.post
                TimelineRowView(
                    post: post, now: now,
                    showsCounts: displaySettings.showsReactionCounts,
                    canDelete: isOwnPost(post),
                    onImageTap: { urls, index in onImageTap(urls, index) },
                    onSelect: { focusedPostID = post.id },
                    onReply: { onReply(post) },
                    onRepost: { Task { await model.toggleRepost(post) } },
                    onQuote: { onQuote(post) },
                    onLike: { Task { await model.toggleLike(post) } },
                    onAvatarTap: { onOpenAuthor(post) },
                    onQuoteTap: { onOpenQuote($0) },
                    onCopyLink: { copyPermalink(post) },
                    onMute: { onMute(post) },
                    onDelete: { pendingDelete = post }
                )
                // Unchanged rows skip re-rendering: the closures are recreated on
                // every parent update and deliberately left out of `==`.
                .equatable()
                // Clicking a row selects it and shows it in the detail pane, as
                // in the prototype. The tap target sits behind the row so its
                // buttons and links keep their own clicks.
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { select(post) }
                }
                .rowHoverHighlight(isFocused: post.id == focusedPostID)
                .overlay(alignment: .top) {
                    // The prototype's inset separator, hidden around the selection.
                    if let previous = previousByID[item.id], post.id != focusedPostID, previous != focusedPostID {
                        Rectangle().fill(theme.divider).frame(height: 1).padding(.leading, 50).padding(.trailing, 8)
                    }
                }
                .padding(.horizontal, 6)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .id(post.id)
                .onAppear {
                    visibleRows.ids.insert(post.id)
                    recordScrollAnchor()
                    if post.id == items.last?.id {
                        Task { await model.loadMore() }
                    }
                }
                .onDisappear {
                    visibleRows.ids.remove(post.id)
                }
            }
            if model.isLoadingMore {
                loadMoreFooter
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { _ in
            restoreScrollIfNeeded(proxy)
        }
    }

    private var loadMoreFooter: some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 14)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("夜空を眺めています…")
                .font(.app(.callout))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func failedState(_ failure: LoadFailure) -> some View {
        VStack(spacing: 10) {
            Image(systemName: Self.icon(for: failure.kind))
                .font(.system(size: 26))
                .foregroundStyle(theme.star)
            Text(failure.title)
                .font(.app(.callout)).foregroundStyle(theme.secondaryText)
            Text(failure.message)
                .font(.app(.caption)).foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("再試行") { Task { await model.load() } }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    /// The SF Symbol that best signals each failure kind.
    private static func icon(for kind: LoadFailure.Kind) -> String {
        switch kind {
        case .offline: return "wifi.slash"
        case .rateLimited: return "hourglass"
        case .server: return "exclamationmark.icloud"
        case .unknown: return "exclamationmark.triangle"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars")
                .font(.system(size: 28))
                .foregroundStyle(theme.tertiaryText)
            Text("まだ投稿がありません")
                .font(.app(.callout)).foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func focusAdjacentPost(_ offset: Int) {
        // Navigate the displayed (thread-grouped) order, not the raw page order.
        let ids = FeedThreading.arrange(model.posts).map(\.id)
        guard !ids.isEmpty else { return }
        if let id = focusedPostID, let index = ids.firstIndex(of: id) {
            let target = max(0, min(ids.count - 1, index + offset))
            focusedPostID = ids[target]
        } else {
            focusedPostID = ids.first
        }
        // Keyboard movement scrolls the focused post into view; a click does not.
        scrollTick += 1
        if focusedPostID == ids.last {
            Task { await model.loadMore() }
        }
    }

    /// Select a row and show it in the detail pane (the prototype's single click).
    private func select(_ post: PostDisplay) {
        focusedPostID = post.id
        onOpenConversation(post)
    }

    private func copyPermalink(_ post: PostDisplay) {
        guard let url = PostPermalink.url(for: post) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
        toastCenter.show("リンクをコピーしました")
    }

    private func actions(for post: PostDisplay) -> PostActions {
        PostActions(
            isLiked: post.viewerLikeURI != nil,
            isReposted: post.viewerRepostURI != nil,
            authorDID: ATURI.repo(post.id),
            authorHandle: post.authorHandle,
            listMembership: listMembership,
            isOwn: isOwnPost(post),
            reply: { onReply(post) },
            repost: { Task { await model.toggleRepost(post) } },
            quote: { onQuote(post) },
            like: { Task { await model.toggleLike(post) } },
            copyLink: { copyPermalink(post) },
            mute: { onMute(post) },
            openInBrowser: {
                if let url = PostPermalink.url(for: post) { NSWorkspace.shared.open(url) }
            }
        )
    }

    /// The post j/k focus currently sits on, if any.
    private var focusedPost: PostDisplay? {
        model.posts.first { $0.id == focusedPostID }
    }

    private var postNavShortcuts: some View {
        ZStack {
            Button("") { focusAdjacentPost(1) }
                .keyboardShortcut("j", modifiers: [])
            Button("") { focusAdjacentPost(-1) }
                .keyboardShortcut("k", modifiers: [])
            Button("") {
                if let post = focusedPost { Task { await model.toggleLike(post) } }
            }
            .keyboardShortcut("l", modifiers: [])
            Button("") {
                if let post = focusedPost, let url = PostPermalink.url(for: post) {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("o", modifiers: [])
            if let onCompose {
                Button("") { onCompose() }
                    .keyboardShortcut("n", modifiers: [])
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
