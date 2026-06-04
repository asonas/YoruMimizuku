import SwiftUI
import HoshidukiyoKit

/// The reply conversation shown in the trailing inspector. Renders the parent
/// post and the tapped reply as a short, vertically connected thread so the
/// reader sees what a post is replying to without the timeline losing width.
struct ThreadInspectorView: View {
    let anchor: PostDisplay
    let now: Date
    var onClose: () -> Void
    var onImageTap: (URL) -> Void = { _ in }

    @EnvironmentObject private var theme: ThemeStore

    /// Parent first, the tapped reply last. Falls back to just the anchor when
    /// the parent could not be resolved (deleted / blocked).
    private var thread: [PostDisplay] {
        if let parent = anchor.replyParent?.post {
            return [parent, anchor]
        }
        return [anchor]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(thread.enumerated()), id: \.element.id) { index, post in
                        PostRowView(
                            post: post,
                            density: .comfortable,
                            now: now,
                            showReplyMarker: false,
                            onImageTap: onImageTap
                        )
                        if index < thread.count - 1 {
                            connector
                        }
                        Divider().overlay(theme.divider)
                    }
                }
            }
        }
        .background(theme.canvas)
        .background(
            Button("", action: onClose)
                .keyboardShortcut(.cancelAction)
                .hidden()
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(theme.accent)
            Text("会話")
                .font(.headline)
                .foregroundStyle(theme.primaryText)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .help("会話を閉じる (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    /// A short thread line joining the parent's avatar column to the reply.
    private var connector: some View {
        HStack {
            Rectangle()
                .fill(theme.divider)
                .frame(width: 2, height: 16)
                .padding(.leading, 16 + 21) // row inset + half avatar
            Spacer()
        }
    }
}
