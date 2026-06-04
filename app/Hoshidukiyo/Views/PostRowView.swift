import SwiftUI
import HoshidukiyoKit

/// One timeline row, rendered compact (Yorufukurou-tight) or comfortable
/// (avatars + action counts) per `DisplayDensity`. Avatars sit in a fixed-width
/// leading column so every row's text aligns; the repost/reply context is a
/// header indented to that same text column.
struct PostRowView: View {
    let post: PostDisplay
    let density: DisplayDensity
    let now: Date
    /// Called with the full-size URL when a thumbnail is tapped, so the host can
    /// present the lightbox.
    var onImageTap: (URL) -> Void = { _ in }
    /// Called with the parent post when the reply marker is tapped, so the host
    /// can open it in a new pane.
    var onReplyTap: (PostDisplay) -> Void = { _ in }

    private let timeFormatter = RelativeTimeFormatter()

    private var relativeTime: String {
        timeFormatter.string(for: post.createdAt, now: now)
    }

    private var avatarSize: CGFloat { density == .compact ? 22 : 40 }
    private var columnSpacing: CGFloat { density == .compact ? 8 : 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 1 : 3) {
            if let context = post.contextLabel {
                Text(context)
                    .font(density == .compact ? .caption2 : .caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .padding(.leading, avatarSize + columnSpacing)
            }
            if let parent = post.replyParent?.post {
                replyMarker(parent: parent)
                    .padding(.leading, avatarSize + columnSpacing)
            }
            HStack(alignment: .top, spacing: columnSpacing) {
                avatar
                content
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, density == .compact ? 5 : 9)
        .padding(.horizontal, density == .compact ? 10 : 12)
    }

    private func replyMarker(parent: PostDisplay) -> some View {
        Button {
            onReplyTap(parent)
        } label: {
            Label("@\(parent.authorHandle) への返信", systemImage: "arrowshape.turn.up.left")
                .font(density == .compact ? .caption2 : .caption)
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .help("リプライ元の投稿を開く")
    }

    private var avatar: some View {
        AsyncImage(url: post.avatarURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Theme.avatarPlaceholder
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 1 : 3) {
            authorLine
            Text(post.body)
                .font(density == .compact ? .callout : .body)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !post.images.isEmpty {
                imageGrid.padding(.top, 2)
            }
            if density == .comfortable {
                actionBar
            }
        }
    }

    @ViewBuilder
    private var imageGrid: some View {
        let columns = post.images.count == 1 ? 1 : 2
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns),
            spacing: 4
        ) {
            ForEach(post.images) { image in
                thumbnail(image)
            }
        }
        .frame(maxWidth: density == .compact ? 320 : 420, alignment: .leading)
    }

    private func thumbnail(_ image: PostImage) -> some View {
        let single = post.images.count == 1
        return AsyncImage(url: image.thumbURL) { phase in
            if let loaded = phase.image {
                loaded.resizable().scaledToFill()
            } else if phase.error != nil {
                Theme.surface.overlay(
                    Image(systemName: "photo").foregroundStyle(Theme.secondaryText)
                )
            } else {
                Theme.surface.overlay(ProgressView().controlSize(.small))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: single ? 220 : 130)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(image.alt.isEmpty ? "画像" : image.alt)
        .onTapGesture {
            if let url = image.fullsizeURL { onImageTap(url) }
        }
    }

    private var authorLine: some View {
        HStack(spacing: density == .compact ? 4 : 5) {
            Text(post.authorDisplayName)
                .font(density == .compact ? .caption : .subheadline).bold()
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
            Text("@\(post.authorHandle) · \(relativeTime)")
                .font(density == .compact ? .caption2 : .subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 22) {
            Label("\(post.replyCount)", systemImage: "arrowshape.turn.up.left")
            Label("\(post.repostCount)", systemImage: "arrow.2.squarepath")
            Label("\(post.likeCount)", systemImage: "heart")
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryText)
        .labelStyle(.titleAndIcon)
        .padding(.top, 2)
    }
}
