import SwiftUI
import YoruMimizukuKit

/// One timeline row, rendered compact (Yorufukurou-tight) or comfortable
/// (avatars + action counts) per `DisplayDensity`. Avatars sit in a fixed-width
/// leading column so every row's text aligns; the repost/reply context is a
/// header indented to that same text column. The whole row lifts gently on hover.
struct PostRowView: View {
    let post: PostDisplay
    let density: DisplayDensity
    let now: Date
    /// Whether to show the "reply to @handle" affordance. Hidden inside the
    /// conversation inspector, where the parent is already on screen.
    var showReplyMarker: Bool = true
    /// Called when a thumbnail is tapped with every full-size URL in the post and
    /// the index of the tapped one, so the host can open the lightbox positioned
    /// on that image and let the viewer page through the rest.
    var onImageTap: ([URL], Int) -> Void = { _, _ in }
    /// Called with the parent post when the reply marker is tapped, so the host
    /// can open the conversation.
    var onReplyTap: (PostDisplay) -> Void = { _ in }

    @EnvironmentObject private var theme: ThemeStore
    @State private var isHovered = false

    private let timeFormatter = RelativeTimeFormatter()

    private var relativeTime: String {
        timeFormatter.string(for: post.createdAt, now: now)
    }

    private var avatarSize: CGFloat { density == .compact ? 24 : 42 }
    private var columnSpacing: CGFloat { density == .compact ? 8 : 11 }
    private var leadingInset: CGFloat { avatarSize + columnSpacing }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 1 : 3) {
            if let context = post.contextLabel {
                contextHeader(context).padding(.leading, leadingInset)
            }
            if showReplyMarker, let parent = post.replyParent?.post {
                replyMarker(parent: parent).padding(.leading, leadingInset)
            }
            HStack(alignment: .top, spacing: columnSpacing) {
                avatar
                content
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, density == .compact ? 6 : 11)
        .padding(.horizontal, density == .compact ? 12 : 16)
        .background(isHovered ? theme.rowHover : .clear)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func contextHeader(_ text: String) -> some View {
        Label(text, systemImage: "arrow.2.squarepath")
            .font(.app(density == .compact ? .caption2 : .caption))
            .foregroundStyle(theme.tertiaryText)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
    }

    private func replyMarker(parent: PostDisplay) -> some View {
        Button {
            onReplyTap(parent)
        } label: {
            Label("@\(parent.authorHandle) への返信", systemImage: "arrowshape.turn.up.left")
                .font(.app(density == .compact ? .caption2 : .caption, weight: .medium))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .help("会話を開く")
    }

    private var avatar: some View {
        RemoteImage(url: post.avatarURL, maxPointSize: avatarSize) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                theme.avatarPlaceholder
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 2 : 4) {
            authorLine
            Text(bodyAttributed)
                .font(.app(density == .compact ? .callout : .body))
                .foregroundStyle(theme.primaryText)
                .tint(theme.accent)
                .lineSpacing(density == .compact ? 1 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !post.images.isEmpty {
                imageGrid.padding(.top, 3)
            }
            if density == .comfortable {
                actionBar
            }
        }
    }

    /// Build the post body as an `AttributedString` so links, hashtags, and
    /// mentions render inline and stay tappable (SwiftUI opens `.link` runs via
    /// the environment's `openURL`). Plain spans keep the body text color.
    private var bodyAttributed: AttributedString {
        post.bodySegments.reduce(into: AttributedString()) { result, segment in
            var run = AttributedString(segment.text)
            if let url = segment.url {
                run.link = url
                run.foregroundColor = theme.accent
            }
            result += run
        }
    }

    @ViewBuilder
    private var imageGrid: some View {
        let columns = post.images.count == 1 ? 1 : 2
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns),
            spacing: 5
        ) {
            ForEach(post.images) { image in
                thumbnail(image)
            }
        }
        .frame(maxWidth: density == .compact ? 320 : 440, alignment: .leading)
    }

    private func thumbnail(_ image: PostImage) -> some View {
        let single = post.images.count == 1
        return RemoteImage(url: image.thumbURL, maxPointSize: single ? 440 : 220) { phase in
            switch phase {
            case .success(let loaded):
                loaded.resizable().scaledToFill()
            case .failure:
                theme.surface.overlay(
                    Image(systemName: "photo").foregroundStyle(theme.secondaryText)
                )
            case .empty:
                theme.surface.overlay(ProgressView().controlSize(.small))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: single ? 240 : 140)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.hairline, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel(image.alt.isEmpty ? "画像" : image.alt)
        .onTapGesture {
            let urls = post.images.compactMap(\.fullsizeURL)
            guard let url = image.fullsizeURL, let index = urls.firstIndex(of: url) else { return }
            onImageTap(urls, index)
        }
    }

    private var authorLine: some View {
        HStack(spacing: density == .compact ? 5 : 6) {
            Text(post.authorDisplayName)
                .font(.app(density == .compact ? .caption : .subheadline, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
            Text("@\(post.authorHandle)")
                .font(.app(density == .compact ? .caption2 : .caption))
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(relativeTime)
                .font(.app(density == .compact ? .caption2 : .caption))
                .foregroundStyle(theme.tertiaryText)
                .monospacedDigit()
        }
    }

    private var actionBar: some View {
        HStack(spacing: 26) {
            Label("\(post.replyCount)", systemImage: "bubble.left")
            Label("\(post.repostCount)", systemImage: "arrow.2.squarepath")
            Label("\(post.likeCount)", systemImage: "heart")
        }
        .font(.app(.caption))
        .foregroundStyle(theme.tertiaryText)
        .labelStyle(.titleAndIcon)
        .monospacedDigit()
        .padding(.top, 3)
    }
}
