import SwiftUI
import BlueskyCore
import YoruMimizukuKit

struct ConversationView: View {
    @ObservedObject var model: ThreadViewModel
    @EnvironmentObject private var displaySettings: DisplaySettingsStore
    let now: Date
    var onImageTap: ([URL], Int) -> Void
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
                    let ancestors = ancestors(of: thread.focus)
                    if !ancestors.isEmpty {
                        Section("Ancestors") {
                            ForEach(ancestors) { ancestor in
                                PostRowView(
                                    post: ancestor,
                                    density: displaySettings.density,
                                    now: now,
                                    interactiveActions: false,
                                    onImageTap: onImageTap,
                                    onOpenThread: onOpenThread,
                                    onOpenAuthor: onOpenAuthor,
                                    onReply: onReply,
                                    onQuote: onQuote,
                                    onToggleLike: nil,
                                    onToggleRepost: nil,
                                    onCopyPermalink: onCopyPermalink,
                                    onOpenPermalink: onOpenPermalink
                                )
                            }
                        }
                    }
                    PostRowView(
                        post: thread.focus,
                        density: displaySettings.density,
                        now: now,
                        isFocused: true,
                        onImageTap: onImageTap,
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
                                    now: now,
                                    onImageTap: onImageTap,
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
        .background { conversationShortcuts }
    }

    private func ancestors(of focus: PostDisplay) -> [PostDisplay] {
        var chain: [PostDisplay] = []
        var current = focus.replyParent?.post
        while let post = current {
            chain.append(post)
            current = post.replyParent?.post
        }
        return chain.reversed()
    }

    private var focusedPost: PostDisplay? {
        if case let .loaded(thread) = model.state { return thread.focus }
        return nil
    }

    private var conversationShortcuts: some View {
        ZStack {
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

private struct ThreadNodeView: View {
    @EnvironmentObject private var displaySettings: DisplaySettingsStore
    let node: ThreadNode
    let now: Date
    var onImageTap: ([URL], Int) -> Void
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
                density: displaySettings.density,
                now: now,
                interactiveActions: false,
                onImageTap: onImageTap,
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
                    now: now,
                    onImageTap: onImageTap,
                    onOpenThread: onOpenThread,
                    onOpenAuthor: onOpenAuthor,
                    onReply: onReply,
                    onQuote: onQuote,
                    onCopyPermalink: onCopyPermalink,
                    onOpenPermalink: onOpenPermalink
                )
            }
            if node.replies.isEmpty, node.post.replyCount > 0 {
                Button {
                    onOpenThread(node.post)
                } label: {
                    Label("さらに表示", systemImage: "ellipsis.bubble")
                }
                .font(.caption)
                .padding(.leading, CGFloat(node.depth + 1) * 18)
                .padding(.vertical, 8)
            }
        }
    }
}
