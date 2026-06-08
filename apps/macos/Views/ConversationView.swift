import SwiftUI
import AppKit
import YoruMimizukuKit

/// One conversation tab's content: the focused post (left-marked as "current")
/// preceded by its full ancestor chain (oldest first, each tappable to re-anchor)
/// and followed by its descendant reply tree. The ancestor chain comes from the
/// recursive `replyParent` links; the reply tree comes from `ConversationThread.replies`,
/// rendered with shallow indentation, a left connector line, a depth cap, and a
/// "さらに表示" re-anchor button for subtrees cut at the cap.
struct ConversationView: View {
    @ObservedObject var model: ThreadViewModel
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var displaySettings: DisplaySettingsStore

    let now: Date
    var onImageTap: ([URL], Int) -> Void
    var onOpenConversation: (PostDisplay) -> Void
    var onOpenAuthor: (PostDisplay) -> Void = { _ in }

    var body: some View {
        content
            .background(theme.canvas)
            .background { conversationShortcuts }
            .task { if case .idle = model.state { await model.load() } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            stateMessage {
                ProgressView().controlSize(.regular)
                Text("会話を読み込んでいます…")
                    .font(.app(.callout)).foregroundStyle(theme.tertiaryText)
            }
        case let .failed(message):
            stateMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26)).foregroundStyle(theme.star)
                Text("会話を読み込めませんでした")
                    .font(.app(.callout)).foregroundStyle(theme.secondaryText)
                Text(message)
                    .font(.app(.caption)).foregroundStyle(theme.tertiaryText)
                    .multilineTextAlignment(.center).frame(maxWidth: 320)
                Button("再試行") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent).tint(theme.accent).padding(.top, 4)
            }
        case let .loaded(thread):
            loaded(thread)
        }
    }

    private func loaded(_ thread: ConversationThread) -> some View {
        let focus = thread.focus
        let ancestors = self.ancestors(of: focus)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if ancestors.isEmpty {
                    rootNotice
                }
                ForEach(ancestors) { ancestor in
                    parentBlock(ancestor)
                    Divider().overlay(theme.divider)
                    connector
                }
                focusBlock(focus)
                Divider().overlay(theme.divider)
                replyTree(thread.replies)
            }
        }
    }

    /// The focused post's ancestors, ordered oldest (thread root) first so they
    /// read top-to-bottom down to the focused post.
    private func ancestors(of focus: PostDisplay) -> [PostDisplay] {
        var chain: [PostDisplay] = []
        var current = focus.replyParent?.post
        while let post = current {
            chain.append(post)
            current = post.replyParent?.post
        }
        return chain.reversed()
    }

    /// An ancestor post, wrapped as a button that re-anchors the tab on it. Image
    /// taps are disabled here so the climb gesture stays unambiguous.
    private func parentBlock(_ parent: PostDisplay) -> some View {
        Button {
            onOpenConversation(parent)
        } label: {
            PostRowView(
                post: parent, density: displaySettings.density, now: now,
                showReplyMarker: false, interactiveActions: false,
                onAvatarTap: { onOpenAuthor(parent) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("@\(parent.authorHandle) の会話を開く")
    }

    private func focusBlock(_ focus: PostDisplay) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(theme.accent).frame(width: 3)
            PostRowView(
                post: focus, density: displaySettings.density, now: now,
                showReplyMarker: false, onImageTap: onImageTap,
                onLike: { Task { await model.toggleLike(focus) } },
                onRepost: { Task { await model.toggleRepost(focus) } },
                onAvatarTap: { onOpenAuthor(focus) },
                onCopyLink: { copyPermalink(focus) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Render the anchor's descendant reply nodes as a shallow indented tree. Each
    /// node is interactive; deeper nodes recurse. A node whose subtree was truncated
    /// at the depth cap (a rendered leaf that still reports replies) gets a
    /// "さらに表示" button that re-anchors the tab on it.
    ///
    /// Returns `AnyView` to break the recursive opaque-type cycle Swift 6 cannot
    /// infer through `some View` for a self-calling function.
    private func replyTree(_ nodes: [ThreadNode]) -> AnyView {
        AnyView(
            ForEach(nodes) { node in
                replyRow(node)
                Divider().overlay(theme.divider)
                if node.replies.isEmpty {
                    if node.post.replyCount > 0 {
                        showMoreButton(node)
                        Divider().overlay(theme.divider)
                    }
                } else {
                    replyTree(node.replies)
                }
            }
        )
    }

    /// One reply node: a left connector line + the post row, inset by its depth so
    /// the thread reads as a shallow outline without running off-screen.
    private func replyRow(_ node: ThreadNode) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(theme.divider)
                .frame(width: 2)
            // Phase D: like/repost on a reply node are intentionally inert — the view model
            // only mutates the focused post. Per-reply re-anchoring by row tap is out of
            // Phase D scope; re-anchoring is available on truncated subtrees via the
            // "さらに表示" button below. Unlike parentBlock (interactiveActions: false),
            // reply rows keep the action bar visible for visual consistency with the focus row.
            PostRowView(
                post: node.post, density: displaySettings.density, now: now,
                showReplyMarker: false, onImageTap: onImageTap,
                onLike: { Task { await model.toggleLike(node.post) } },
                onRepost: { Task { await model.toggleRepost(node.post) } },
                onAvatarTap: { onOpenAuthor(node.post) },
                onCopyLink: { copyPermalink(node.post) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(node.depth + 1) * indentStep)
    }

    /// Re-anchor cue for a subtree that was cut at the depth cap. Tapping opens the
    /// node as a fresh conversation anchor (reusing the existing re-anchor path),
    /// which reloads it with its own descendants.
    private func showMoreButton(_ node: ThreadNode) -> some View {
        Button {
            onOpenConversation(node.post)
        } label: {
            Label("さらに表示", systemImage: "ellipsis.bubble")
                .font(.app(.caption))
                .foregroundStyle(theme.accent)
        }
        .buttonStyle(.plain)
        .padding(.leading, CGFloat(node.depth + 2) * indentStep)
        .padding(.vertical, 8)
    }

    /// One indentation step for the reply tree. Modest so deep trees stay readable.
    private var indentStep: CGFloat { 18 }

    private var connector: some View {
        HStack {
            Rectangle()
                .fill(theme.divider)
                .frame(width: 2, height: 14)
                .padding(.leading, 16 + 21) // row inset + half avatar
            Spacer()
        }
    }

    private var rootNotice: some View {
        Label("これがスレッドの起点です", systemImage: "flag")
            .font(.app(.caption))
            .foregroundStyle(theme.tertiaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }

    /// The conversation's anchor (focused) post, available only once loaded.
    private var focusedPost: PostDisplay? {
        if case let .loaded(thread) = model.state { return thread.focus }
        return nil
    }

    private func copyPermalink(_ post: PostDisplay) {
        guard let url = PostPermalink.url(for: post) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }

    /// Hidden f/o shortcuts that act on the anchor post, mirroring FeedView.
    private var conversationShortcuts: some View {
        ZStack {
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
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func stateMessage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 10) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 60)
    }
}
