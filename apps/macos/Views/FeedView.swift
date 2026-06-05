import SwiftUI
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
    let now: Date
    var onImageTap: ([URL], Int) -> Void
    var onOpenConversation: (PostDisplay) -> Void
    /// Optional n-key new-post handler; when nil the shortcut is omitted.
    var onCompose: (() -> Void)? = nil
    /// Opens the quote composer for a post (from the repost menu).
    var onQuote: (PostDisplay) -> Void = { _ in }

    @State private var focusedPostID: String?

    private let refreshInterval: Duration = .seconds(30)

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title) { EmptyView() }
            timeline
        }
        .background(theme.canvas)
        .ignoresSafeArea(.container, edges: .top)
        .background { postNavShortcuts }
        .task { await runFeed() }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                switch model.state {
                case .idle, .loading:
                    loadingState
                case let .failed(message):
                    failedState(message)
                case let .loaded(posts):
                    if posts.isEmpty {
                        emptyState
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

    private func postList(_ posts: [PostDisplay]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(posts) { post in
                PostRowView(
                    post: post, density: displaySettings.density, now: now,
                    onImageTap: { urls, index in
                        focusedPostID = post.id
                        onImageTap(urls, index)
                    },
                    onReplyTap: { _ in onOpenConversation(post) },
                    onSelect: { focusedPostID = post.id },
                    onLike: { Task { await model.toggleLike(post) } },
                    onRepost: { Task { await model.toggleRepost(post) } },
                    onQuote: { onQuote(post) }
                )
                // Clicking the row's open area moves j/k focus here, so navigation
                // resumes from the post the user just clicked.
                .contentShape(Rectangle())
                .onTapGesture { focusedPostID = post.id }
                .background(post.id == focusedPostID ? theme.rowHover : .clear)
                .overlay(alignment: .leading) {
                    if post.id == focusedPostID {
                        Rectangle().fill(theme.accent).frame(width: 3)
                    }
                }
                .id(post.id)
                .onAppear {
                    if post.id == posts.last?.id {
                        Task { await model.loadMore() }
                    }
                }
                Divider().overlay(theme.divider)
            }
            if model.isLoadingMore {
                loadMoreFooter
            }
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

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26))
                .foregroundStyle(theme.star)
            Text("読み込みに失敗しました")
                .font(.app(.callout)).foregroundStyle(theme.secondaryText)
            Text(message)
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

    /// Load once, then refresh on an interval while on screen. SwiftUI cancels this
    /// on disappear; returning re-runs it (the initial load is skipped once loaded).
    private func runFeed() async {
        if case .idle = model.state { await model.load() }
        if focusedPostID == nil { focusedPostID = model.posts.first?.id }
        while !Task.isCancelled {
            try? await Task.sleep(for: refreshInterval)
            if Task.isCancelled { break }
            await model.refresh()
        }
    }

    private func focusAdjacentPost(_ offset: Int) {
        let posts = model.posts
        guard !posts.isEmpty else { return }
        if let id = focusedPostID, let index = posts.firstIndex(where: { $0.id == id }) {
            let target = max(0, min(posts.count - 1, index + offset))
            focusedPostID = posts[target].id
        } else {
            focusedPostID = posts.first?.id
        }
        if focusedPostID == posts.last?.id {
            Task { await model.loadMore() }
        }
    }

    private var postNavShortcuts: some View {
        ZStack {
            Button("") { focusAdjacentPost(1) }
                .keyboardShortcut("j", modifiers: [])
            Button("") { focusAdjacentPost(-1) }
                .keyboardShortcut("k", modifiers: [])
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
