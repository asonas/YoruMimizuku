import SwiftUI
import YoruMimizukuKit

struct TimelineListView: View {
    @ObservedObject var model: TimelineViewModel
    let title: String
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
            case let .failed(message):
                ContentUnavailableView("読み込みに失敗しました", systemImage: "exclamationmark.triangle", description: Text(message))
                    .toolbar {
                        Button("再試行") { Task { await model.load() } }
                    }
            case let .loaded(posts):
                List {
                    ForEach(posts) { post in
                        PostRowView(
                            post: post,
                            isFocused: focusedPostID == post.id,
                            onOpenThread: onOpenThread,
                            onOpenAuthor: onOpenAuthor,
                            onReply: onReply,
                            onQuote: onQuote,
                            onToggleLike: { post in Task { await model.toggleLike(post) } },
                            onToggleRepost: { post in Task { await model.toggleRepost(post) } },
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
                .toolbar {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("更新", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            Button {
                moveFocus(delta: -1)
            } label: {
                Label("前へ", systemImage: "chevron.up")
            }
            .keyboardShortcut("k", modifiers: [])

            Button {
                moveFocus(delta: 1)
            } label: {
                Label("次へ", systemImage: "chevron.down")
            }
            .keyboardShortcut("j", modifiers: [])

            Button {
                if let post = focusedPost {
                    Task { await model.toggleLike(post) }
                }
            } label: {
                Label("いいね", systemImage: "heart")
            }
            .keyboardShortcut("f", modifiers: [])

            Button {
                if let post = focusedPost { onOpenPermalink(post) }
            } label: {
                Label("ブラウザ", systemImage: "safari")
            }
            .keyboardShortcut("o", modifiers: [])
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
    }
}
