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

    @State private var focusedPostID: String?
    /// The own-post the viewer asked to delete, pending confirmation. Set by a
    /// row's context menu; cleared when the dialog is dismissed or the delete runs.
    @State private var pendingDelete: PostDisplay?

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                DetailHeader(title) { EmptyView() }
            }
            timeline
        }
        .background(theme.canvas)
        .ignoresSafeArea(.container, edges: .top)
        .background { postNavShortcuts }
        .onChange(of: model.state) { _, _ in
            if focusedPostID == nil { focusedPostID = FeedThreading.arrange(model.posts).first?.id }
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
                        postList(posts)
                    }
                }
            }
            .onChange(of: focusedPostID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    /// The loaded feed. Uses `List` rather than `ScrollView { LazyVStack }`: with a
    /// LazyVStack, rows whose height was first estimated (before the row was actually
    /// measured) keep that stale slot height until a full re-layout — a normal body
    /// re-render (e.g. the per-second `now` tick) does not revisit it — leaving a
    /// blank gap below the row that only collapses on scroll or scene-phase change.
    /// `List` measures variable row heights correctly and recycles rows, so the gap
    /// never appears and memory stays bounded.
    private func postList(_ posts: [PostDisplay]) -> some View {
        // Same-thread posts are regrouped the way Bluesky's web feed shows them
        // (oldest first within the block, connector line, no divider inside).
        let items = FeedThreading.arrange(posts)
        return List {
            ForEach(items) { item in
                let post = item.post
                VStack(alignment: .leading, spacing: 0) {
                    PostRowView(
                        post: post, density: displaySettings.density, now: now,
                        onImageTap: { urls, index in
                            focusedPostID = post.id
                            onImageTap(urls, index)
                        },
                        onReplyTap: { target in
                            if target.id == post.id {
                                onReply(post)
                            } else {
                                onOpenConversation(target)
                            }
                        },
                        onSelect: { focusedPostID = post.id },
                        onLike: { Task { await model.toggleLike(post) } },
                        onRepost: { Task { await model.toggleRepost(post) } },
                        onQuote: { onQuote(post) },
                        onAvatarTap: { onOpenAuthor(post) },
                        onCopyLink: { copyPermalink(post) },
                        onQuoteTap: { onOpenQuote($0) },
                        canDelete: isOwnPost(post),
                        onDelete: { pendingDelete = post },
                        connectsToPrevious: item.connectsToPrevious,
                        connectsToNext: item.connectsToNext
                    )
                    // Skip re-rendering rows whose data is unchanged: PostRowView is
                    // Equatable on its value inputs, so a parent re-render that only
                    // recreates the closures no longer re-typesets every visible row.
                    .equatable()
                    // Clicking the row's open area moves j/k focus here, so navigation
                    // resumes from the post the user just clicked.
                    .contentShape(Rectangle())
                    .onTapGesture { focusedPostID = post.id }
                    // Focus + hover highlight in an isolated layer: hovering rows
                    // during a scroll re-renders only this background, not the row
                    // body (which stays cached via `.equatable()`).
                    .rowHoverHighlight(isFocused: post.id == focusedPostID)
                    // Rows joined by the thread line read as one block; the divider
                    // only closes the block (or separates standalone rows).
                    if !item.connectsToNext {
                        Divider().overlay(theme.divider)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .id(post.id)
                .onAppear {
                    if post.id == items.last?.id {
                        Task { await model.loadMore() }
                    }
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
        if focusedPostID == ids.last {
            Task { await model.loadMore() }
        }
    }

    private func copyPermalink(_ post: PostDisplay) {
        guard let url = PostPermalink.url(for: post) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
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
            .keyboardShortcut("f", modifiers: [])
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
