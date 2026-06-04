import SwiftUI
import YoruMimizukuKit

/// One conversation tab's content: the focused post (left-marked as "current")
/// plus its immediate parent. Tapping the parent opens a new tab anchored on it,
/// whose own fetch reveals the next ancestor — so the reply tree is climbed
/// recursively, one tab per level.
struct ConversationView: View {
    @ObservedObject var model: ThreadViewModel
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var displaySettings: DisplaySettingsStore

    let title: String
    let now: Date
    var onImageTap: (URL) -> Void
    var onOpenConversation: (PostDisplay) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader("会話 · \(title)", systemImage: "bubble.left.and.bubble.right.fill") {
                ChromeIconButton(systemImage: "xmark", help: "このタブを閉じる", action: onClose)
            }
            content
        }
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
                    .font(.callout).foregroundStyle(theme.tertiaryText)
            }
        case let .failed(message):
            stateMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26)).foregroundStyle(theme.star)
                Text("会話を読み込めませんでした")
                    .font(.callout).foregroundStyle(theme.secondaryText)
                Text(message)
                    .font(.caption).foregroundStyle(theme.tertiaryText)
                    .multilineTextAlignment(.center).frame(maxWidth: 320)
                Button("再試行") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent).tint(theme.accent).padding(.top, 4)
            }
        case let .loaded(focus):
            loaded(focus)
        }
    }

    private func loaded(_ focus: PostDisplay) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let parent = focus.replyParent?.post {
                    parentBlock(parent)
                    Divider().overlay(theme.divider)
                    connector
                }
                focusBlock(focus)
                Divider().overlay(theme.divider)
                if focus.replyParent == nil {
                    rootNotice
                }
            }
        }
    }

    /// The parent post, wrapped as a button that climbs to its own conversation.
    /// Image taps are disabled here so the climb gesture stays unambiguous.
    private func parentBlock(_ parent: PostDisplay) -> some View {
        Button {
            onOpenConversation(parent)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Label("親の投稿を開いて遡る", systemImage: "arrow.up")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                PostRowView(post: parent, density: displaySettings.density, now: now, showReplyMarker: false)
            }
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
                showReplyMarker: false, onImageTap: onImageTap
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
            .font(.caption)
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
