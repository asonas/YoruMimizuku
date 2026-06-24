import SwiftUI
import YoruMimizukuKit

struct TimelineListView: View {
    @ObservedObject var model: TimelineViewModel
    @EnvironmentObject private var displaySettings: DisplaySettingsStore
    let title: String
    let now: Date
    var onImageTap: ([URL], Int) -> Void
    var onOpenThread: (PostDisplay) -> Void
    var onOpenAuthor: (String, String, String?, URL?) -> Void
    var onReply: (PostDisplay) -> Void
    var onQuote: (PostDisplay) -> Void
    var onCopyPermalink: (PostDisplay) -> Void
    var onOpenPermalink: (PostDisplay) -> Void

    @State private var focusedPostID: String?

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView()
                    .task { await model.load() }
            case let .failed(failure):
                ContentUnavailableView(failure.title, systemImage: "exclamationmark.triangle", description: Text(failure.message))
                    .overlay(alignment: .bottom) {
                        Button("再試行") { Task { await model.load() } }
                            .buttonStyle(.borderedProminent)
                            .padding()
                    }
            case let .loaded(posts):
                List {
                    ForEach(posts) { post in
                        PostRowView(
                            post: post,
                            density: displaySettings.density,
                            now: now,
                            isFocused: focusedPostID == post.id,
                            onImageTap: onImageTap,
                            onOpenThread: onOpenThread,
                            onOpenAuthor: onOpenAuthor,
                            onReply: onReply,
                            onQuote: onQuote,
                            onToggleLike: { post in Task { await model.toggleLike(post) } },
                            onToggleRepost: { post in Task { await model.toggleRepost(post) } },
                            onReplyMarkerTap: onOpenThread,
                            onCopyPermalink: onCopyPermalink,
                            onOpenPermalink: onOpenPermalink
                        )
                        .listRowSeparator(.visible)
                        .onAppear {
                            if focusedPostID == nil { focusedPostID = post.id }
                            if post.id == posts.last?.id, model.canLoadMore {
                                Task { await model.loadMore() }
                            }
                        }
                    }
                    if model.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await model.refresh() }
            }
        }
        .navigationTitle(title)
        .background { keyboardShortcuts }
        .onChange(of: model.state) { _, _ in
            if focusedPostID == nil { focusedPostID = model.posts.first?.id }
        }
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
