import SwiftUI
import BlueskyCore
import YoruMimizukuKit

struct ConversationView: View {
    @ObservedObject var model: ThreadViewModel
    var onOpenThread: (PostDisplay) -> Void
    var onOpenAuthor: (String, String, String?, URL?) -> Void
    var onReply: (PostDisplay) -> Void
    var onQuote: (PostDisplay) -> Void
    var onCopyPermalink: (PostDisplay) -> Void
    var onOpenPermalink: (PostDisplay) -> Void

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView()
                    .task { await model.load() }
            case let .failed(message):
                ContentUnavailableView("会話を読み込めませんでした", systemImage: "exclamationmark.bubble", description: Text(message))
            case let .loaded(thread):
                List {
                    PostRowView(
                        post: thread.focus,
                        isFocused: true,
                        onOpenThread: onOpenThread,
                        onOpenAuthor: onOpenAuthor,
                        onReply: onReply,
                        onQuote: onQuote,
                        onToggleLike: { post in Task { await model.toggleLike(post) } },
                        onToggleRepost: { post in Task { await model.toggleRepost(post) } },
                        onCopyPermalink: onCopyPermalink,
                        onOpenPermalink: onOpenPermalink
                    )
                    if !thread.replies.isEmpty {
                        Section("Replies") {
                            ForEach(thread.replies) { node in
                                ThreadNodeView(
                                    node: node,
                                    onOpenThread: onOpenThread,
                                    onOpenAuthor: onOpenAuthor,
                                    onReply: onReply,
                                    onQuote: onQuote,
                                    onCopyPermalink: onCopyPermalink,
                                    onOpenPermalink: onOpenPermalink
                                )
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await model.load() }
            }
        }
        .navigationTitle("Conversation")
    }
}

private struct ThreadNodeView: View {
    let node: ThreadNode
    var onOpenThread: (PostDisplay) -> Void
    var onOpenAuthor: (String, String, String?, URL?) -> Void
    var onReply: (PostDisplay) -> Void
    var onQuote: (PostDisplay) -> Void
    var onCopyPermalink: (PostDisplay) -> Void
    var onOpenPermalink: (PostDisplay) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PostRowView(
                post: node.post,
                onOpenThread: onOpenThread,
                onOpenAuthor: onOpenAuthor,
                onReply: onReply,
                onQuote: onQuote,
                onToggleLike: nil,
                onToggleRepost: nil,
                onCopyPermalink: onCopyPermalink,
                onOpenPermalink: onOpenPermalink
            )
            .padding(.leading, CGFloat(node.depth) * 18)
            ForEach(node.replies) { child in
                ThreadNodeView(
                    node: child,
                    onOpenThread: onOpenThread,
                    onOpenAuthor: onOpenAuthor,
                    onReply: onReply,
                    onQuote: onQuote,
                    onCopyPermalink: onCopyPermalink,
                    onOpenPermalink: onOpenPermalink
                )
            }
        }
    }
}
