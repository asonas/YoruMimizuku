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
    /// Whether the action bar is tappable (like / repost / quote / open conversation).
    /// Set false where the row is itself wrapped in a button (conversation ancestors)
    /// so the counts render as plain labels and avoid nested-button ambiguity.
    var interactiveActions: Bool = true
    /// Called when a thumbnail is tapped with every full-size URL in the post and
    /// the index of the tapped one, so the host can open the lightbox positioned
    /// on that image and let the viewer page through the rest.
    var onImageTap: ([URL], Int) -> Void = { _, _ in }
    /// Called with the parent post when the reply marker is tapped, so the host
    /// can open the conversation.
    var onReplyTap: (PostDisplay) -> Void = { _ in }
    /// Called when this row is activated (action tapped or image opened) so the
    /// host can move keyboard focus (j/k) to it.
    var onSelect: () -> Void = {}
    /// Called when the like action is tapped (toggles the viewer's like).
    var onLike: () -> Void = {}
    /// Called when "リポスト" is chosen from the repost menu (toggles the repost).
    var onRepost: () -> Void = {}
    /// Called when "引用" is chosen from the repost menu (opens the quote composer).
    var onQuote: () -> Void = {}
    /// Called when the author avatar is tapped, so the host can open the author tab.
    var onAvatarTap: () -> Void = {}
    /// Called when the copy-link icon is tapped (copies the post permalink).
    var onCopyLink: () -> Void = {}

    @EnvironmentObject private var theme: ThemeStore
    @State private var isHovered = false
    @State private var showRepostOptions = false

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
        .contentShape(Circle())
        .onTapGesture { onAvatarTap() }
        .help("@\(post.authorHandle) のページを開く")
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 2 : 4) {
            authorLine
            // The body's characters (the costly UTF-8 build) are precomputed on
            // `PostDisplay`; here we only re-apply the link color, which mutates run
            // attributes without rebuilding the string.
            //
            // No `.textSelection(.enabled)`: on macOS a selectable `Text` and
            // tappable `.link` runs are mutually incompatible — once the row
            // re-lays-out (e.g. focus toggling its background) the link spans render
            // blank, so URLs vanish on focus and become unclickable. Links win over
            // body selection here; the copy-link action covers sharing a post.
            Text(bodyAttributed)
                .font(.app(density == .compact ? .callout : .body))
                .foregroundStyle(theme.primaryText)
                .tint(theme.accent)
                .lineSpacing(density == .compact ? 1 : 2)
                .fixedSize(horizontal: false, vertical: true)
            if !post.images.isEmpty {
                imageGrid.padding(.top, 3)
            }
            if density == .comfortable {
                if interactiveActions {
                    actionBar
                } else {
                    staticActionBar
                }
            }
        }
    }

    /// The precomputed body with link spans tinted to the accent color. Starting
    /// from `post.bodyAttributedString` keeps the expensive character build cached
    /// on `PostDisplay`; coloring lives here because the color is theme-derived and
    /// only touches run attributes. Iterating `attributed.runs` reads a snapshot
    /// taken before the first mutation (copy-on-write), so it is safe to mutate
    /// `attributed` inside the loop.
    private var bodyAttributed: AttributedString {
        var attributed = post.bodyAttributedString
        for run in attributed.runs where run.link != nil {
            attributed[run.range].foregroundColor = theme.accent
        }
        return attributed
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
            onSelect()
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
            Button {
                onSelect()
                onReplyTap(post)
            } label: {
                actionLabel("\(post.replyCount)", systemImage: "bubble.left")
            }
            .help("会話を開く")

            // A plain Button (not a Menu) so it inherits the same caption font and
            // metrics as the reply/like buttons — a macOS `Menu` renders its label
            // through a control that ignores the SwiftUI font, making it larger. The
            // repost / quote choice opens in a popover instead.
            Button {
                onSelect()
                showRepostOptions = true
            } label: {
                actionLabel("\(post.repostCount)", systemImage: "arrow.2.squarepath",
                            active: post.isReposted, activeColor: theme.accent)
            }
            .help(post.isReposted ? "リポスト済み" : "リポスト / 引用")
            .popover(isPresented: $showRepostOptions, arrowEdge: .bottom) {
                repostOptions
            }

            Button {
                onSelect()
                onLike()
            } label: {
                actionLabel("\(post.likeCount)", systemImage: post.isLiked ? "heart.fill" : "heart",
                            active: post.isLiked, activeColor: theme.star)
            }
            .help(post.isLiked ? "いいねを取り消す" : "いいね")

            Button {
                onSelect()
                onCopyLink()
            } label: {
                Image(systemName: "link")
                    .foregroundStyle(theme.tertiaryText)
            }
            .help("リンクをコピー")
        }
        .font(.app(.caption))
        .labelStyle(.titleAndIcon)
        .monospacedDigit()
        .buttonStyle(.plain)
        .padding(.top, 3)
    }

    /// The repost / quote choices shown in the popover anchored to the repost button.
    private var repostOptions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                showRepostOptions = false
                onRepost()
            } label: {
                Label(post.isReposted ? "リポストを取り消す" : "リポスト", systemImage: "arrow.2.squarepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            Button {
                showRepostOptions = false
                onQuote()
            } label: {
                Label("引用", systemImage: "quote.bubble")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .font(.app(.callout))
        .labelStyle(.titleAndIcon)
        .buttonStyle(.plain)
        .padding(8)
        .frame(width: 200)
    }

    /// Non-interactive action bar (counts only), used for conversation ancestor rows
    /// that are themselves wrapped in a re-anchor button.
    private var staticActionBar: some View {
        HStack(spacing: 26) {
            actionLabel("\(post.replyCount)", systemImage: "bubble.left")
            actionLabel("\(post.repostCount)", systemImage: "arrow.2.squarepath", active: post.isReposted, activeColor: theme.accent)
            actionLabel("\(post.likeCount)", systemImage: post.isLiked ? "heart.fill" : "heart", active: post.isLiked, activeColor: theme.star)
        }
        .font(.app(.caption))
        .labelStyle(.titleAndIcon)
        .monospacedDigit()
        .padding(.top, 3)
    }

    /// One action-bar label: tinted `activeColor` when the viewer has acted on the
    /// post (liked / reposted), otherwise the muted tertiary text color.
    private func actionLabel(
        _ text: String, systemImage: String, active: Bool = false, activeColor: Color? = nil
    ) -> some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(active ? (activeColor ?? theme.accent) : theme.tertiaryText)
    }
}
