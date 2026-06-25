import SwiftUI
import BlueskyCore
import YoruMimizukuKit

struct TimelineListView: View {
    @ObservedObject var model: TimelineViewModel
    @EnvironmentObject private var displaySettings: DisplaySettingsStore
    @EnvironmentObject private var theme: ThemeStore
    let now: Date
    /// The signed-in account's DID. Rows whose author DID matches gain a "削除"
    /// context-menu action. Nil disables delete everywhere.
    var currentDID: String?
    var onImageTap: ([URL], Int) -> Void
    var onOpenThread: (PostDisplay) -> Void
    var onOpenAuthor: (String, String, String?, URL?) -> Void
    var onReply: (PostDisplay) -> Void
    var onQuote: (PostDisplay) -> Void
    var onCopyPermalink: (PostDisplay) -> Void
    var onOpenPermalink: (PostDisplay) -> Void

    @State private var focusedPostID: String?
    @State private var contentWidth: CGFloat = 0
    /// The own-post the viewer asked to delete, pending confirmation.
    @State private var pendingDelete: PostDisplay?

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                loadingState
                    .task { await model.load() }
            case let .failed(failure):
                failedState(failure)
            case let .loaded(posts):
                if posts.isEmpty {
                    emptyState
                } else {
                    postList(posts)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.canvas)
        .background { keyboardShortcuts }
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

    /// Whether `post` is one of the signed-in account's own posts.
    private func isOwnPost(_ post: PostDisplay) -> Bool {
        guard let currentDID, let repo = ATURI.repo(post.id) else { return false }
        return repo == currentDID
    }

    /// The loaded feed, with same-thread posts regrouped the way Bluesky's web feed
    /// shows them (oldest first within the block, connector line, no divider inside).
    private func postList(_ posts: [PostDisplay]) -> some View {
        let items = FeedThreading.arrange(posts)
        return List {
            ForEach(items) { item in
                let post = item.post
                VStack(alignment: .leading, spacing: 0) {
                    PostRowView(
                        post: post,
                        density: displaySettings.density,
                        now: now,
                        isFocused: focusedPostID == post.id,
                        connectsToPrevious: item.connectsToPrevious,
                        connectsToNext: item.connectsToNext,
                        canDelete: isOwnPost(post),
                        contentWidth: contentWidth,
                        onImageTap: onImageTap,
                        onOpenThread: onOpenThread,
                        onOpenAuthor: onOpenAuthor,
                        onReply: onReply,
                        onQuote: onQuote,
                        onToggleLike: { post in Task { await model.toggleLike(post) } },
                        onToggleRepost: { post in Task { await model.toggleRepost(post) } },
                        onReplyMarkerTap: onOpenThread,
                        onCopyPermalink: onCopyPermalink,
                        onOpenPermalink: onOpenPermalink,
                        onDelete: { pendingDelete = $0 }
                    )
                    if !item.connectsToNext {
                        Divider().overlay(theme.divider)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .id(post.id)
                .onAppear {
                    if focusedPostID == nil { focusedPostID = post.id }
                    if post.id == items.last?.id, model.canLoadMore {
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
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            contentWidth = newWidth
        }
        .refreshable { await model.refresh() }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var focusedPost: PostDisplay? {
        model.posts.first { $0.id == focusedPostID } ?? model.posts.first
    }

    private func moveFocus(delta: Int) {
        let posts = model.posts
        guard !posts.isEmpty else { return }
        let currentIndex = focusedPostID.flatMap { id in posts.firstIndex { $0.id == id } } ?? 0
        let next = min(max(currentIndex + delta, 0), posts.count - 1)
        focusedPostID = posts[next].id
        if focusedPostID == posts.last?.id, model.canLoadMore {
            Task { await model.loadMore() }
        }
    }

    private var keyboardShortcuts: some View {
        ZStack {
            Button("") { moveFocus(delta: -1) }
                .keyboardShortcut("k", modifiers: [])
            Button("") { moveFocus(delta: 1) }
                .keyboardShortcut("j", modifiers: [])
            Button("") {
                if let post = focusedPost { Task { await model.toggleLike(post) } }
            }
            .keyboardShortcut("f", modifiers: [])
            Button("") {
                if let post = focusedPost { onOpenPermalink(post) }
            }
            .keyboardShortcut("o", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
