import SwiftUI
import YoruMimizukuKit

/// One conversation tab's content: the focused post (left-marked as "current")
/// preceded by its full ancestor chain, oldest first, up to the thread root. Each
/// ancestor is tappable to re-anchor the tab on it. The chain is built from the
/// recursive `replyParent` links the thread fetch hydrates in one request.
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
        case let .loaded(focus):
            loaded(focus)
        }
    }

    private func loaded(_ focus: PostDisplay) -> some View {
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
                onAvatarTap: { onOpenAuthor(focus) }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

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

    private func stateMessage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 10) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 60)
    }
}
