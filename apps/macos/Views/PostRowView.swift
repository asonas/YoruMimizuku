import SwiftUI
import YoruMimizukuKit

/// One timeline row, rendered compact (Yorufukurou-tight) or comfortable
/// (avatars + action counts) per `DisplayDensity`. Avatars sit in a fixed-width
/// leading column so every row's text aligns; the repost/reply context is a
/// header indented to that same text column. The whole row lifts gently on hover.
struct PostRowView: View, @MainActor Equatable {
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
    /// Thread-grouping flags (see `FeedThreading`): when set, a member of the
    /// same reply chain sits directly above / below, and the avatar column draws
    /// the Bluesky-web-style connector line toward it. The reply marker is
    /// redundant when the parent is the row right above, so it is hidden.
    var connectsToPrevious: Bool = false
    var connectsToNext: Bool = false

    @EnvironmentObject private var theme: ThemeStore
    @State private var showRepostOptions = false

    private let timeFormatter = RelativeTimeFormatter()

    private var relativeTime: String {
        timeFormatter.string(for: post.createdAt, now: now)
    }

    private var avatarSize: CGFloat { density == .compact ? 24 : 42 }
    private var columnSpacing: CGFloat { density == .compact ? 8 : 11 }
    private var leadingInset: CGFloat { avatarSize + columnSpacing }

    /// The row's rendered output depends only on these value inputs (plus the
    /// theme environment and local @State, which SwiftUI tracks separately). The
    /// closures are deliberately excluded: `FeedView` recreates them on every
    /// parent update, and comparing them would defeat the whole point — without
    /// this, an unchanged row re-runs a full text re-typeset on every tick.
    ///
    /// We compare `post` by `id` plus only its mutable, display-affecting fields
    /// rather than with `PostDisplay`'s synthesized `==`. A post's URI (`id`) keys
    /// immutable content (text, author, images, createdAt), so the full deep
    /// compare — which walks the whole `bodyAttributedString` every call — is pure
    /// overhead on a hot path; only counts and the viewer's like/repost state ever
    /// change in place (optimistic updates).
    static func == (lhs: PostRowView, rhs: PostRowView) -> Bool {
        lhs.post.id == rhs.post.id
            && lhs.post.replyCount == rhs.post.replyCount
            && lhs.post.repostCount == rhs.post.repostCount
            && lhs.post.likeCount == rhs.post.likeCount
            && lhs.post.viewerLikeURI == rhs.post.viewerLikeURI
            && lhs.post.viewerRepostURI == rhs.post.viewerRepostURI
            && lhs.density == rhs.density
            && lhs.now == rhs.now
            && lhs.showReplyMarker == rhs.showReplyMarker
            && lhs.interactiveActions == rhs.interactiveActions
            && lhs.connectsToPrevious == rhs.connectsToPrevious
            && lhs.connectsToNext == rhs.connectsToNext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 1 : 3) {
            if let context = post.contextLabel {
                contextHeader(context).padding(.leading, leadingInset)
            }
            if showReplyMarker, !connectsToPrevious, let parent = post.replyParent?.post {
                replyMarker(parent: parent).padding(.leading, leadingInset)
            }
            HStack(alignment: .top, spacing: columnSpacing) {
                avatarColumn
                content
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, density == .compact ? 12 : 16)
    }

    private var verticalPadding: CGFloat { density == .compact ? 6 : 11 }

    /// The avatar plus the thread connector segments. The top segment reaches
    /// back through the row's own top padding to meet the previous row's line;
    /// the bottom segment stretches to the row's bottom edge and through the
    /// bottom padding so the line is continuous across grouped rows (the feed
    /// also drops the divider between them).
    private var avatarColumn: some View {
        VStack(spacing: 0) {
            if connectsToPrevious {
                threadLine
                    .frame(height: verticalPadding)
                    .padding(.top, -verticalPadding)
            }
            avatar
            if connectsToNext {
                threadLine
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, -verticalPadding)
            }
        }
        .frame(width: avatarSize)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var threadLine: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(theme.hairline)
            .frame(width: 2)
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
            // The external-link card sits below the body and images and above the
            // action bar. A post with its own external embed renders it directly;
            // otherwise a bare link in a text-only post resolves its OGP preview
            // lazily (image posts skip the fallback to keep rows tight).
            if let card = post.linkCard {
                LinkCardView(card: card, density: density).padding(.top, 3)
            } else if post.images.isEmpty, let url = post.firstLinkURL {
                LazyLinkCardView(url: url, density: density).padding(.top, 3)
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


    private var imageMaxWidth: CGFloat { density == .compact ? 320 : 440 }

    @ViewBuilder
    private var imageGrid: some View {
        // A lone image is laid out at its true aspect ratio (see `singleImage`); two
        // or more share the fixed-height cover-cropped grid where uniform tiles read
        // better than mismatched proportions.
        if post.images.count == 1, let image = post.images.first {
            singleImage(image)
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 2),
                spacing: 5
            ) {
                ForEach(post.images) { image in
                    thumbnail(image, height: 140, maxPointSize: 220)
                }
            }
            .frame(maxWidth: imageMaxWidth, alignment: .leading)
        }
    }

    /// A single attached image, sized to its real aspect ratio so wide images show
    /// in full (no left/right crop or overflow) and tall images fill the column
    /// width with only a slight crop. The ratio is clamped so an extreme panorama or
    /// portrait can't make the row absurdly short or tall; within the clamp the image
    /// fills its box exactly (cover == contain), so a crop only ever touches the
    /// clamped extreme. The decode size follows the box's longer edge to stay sharp.
    private func singleImage(_ image: PostImage) -> some View {
        let ratio = min(max(image.aspectRatio ?? 4.0 / 3.0, 0.7), 5.0)
        let decodeEdge = max(imageMaxWidth, imageMaxWidth / ratio)
        return RemoteImage(url: image.thumbURL, maxPointSize: decodeEdge) { phase in
            imagePhaseContent(phase)
        }
        .aspectRatio(ratio, contentMode: .fit)
        .frame(maxWidth: imageMaxWidth, alignment: .leading)
        .clipped()
        .modifier(ThumbnailChrome(alt: image.alt) { openLightbox(at: image) })
    }

    private func thumbnail(_ image: PostImage, height: CGFloat, maxPointSize: CGFloat) -> some View {
        RemoteImage(url: image.thumbURL, maxPointSize: maxPointSize) { phase in
            imagePhaseContent(phase)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .modifier(ThumbnailChrome(alt: image.alt) { openLightbox(at: image) })
    }

    /// The loaded / failed / loading appearance shared by single and grid thumbnails.
    @ViewBuilder
    private func imagePhaseContent(_ phase: RemoteImagePhase) -> some View {
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

    /// Open the lightbox positioned on `image`, moving keyboard focus to this row.
    private func openLightbox(at image: PostImage) {
        onSelect()
        let urls = post.images.compactMap(\.fullsizeURL)
        guard let url = image.fullsizeURL, let index = urls.firstIndex(of: url) else { return }
        onImageTap(urls, index)
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

/// Draws a row's focus + hover highlight in a layer whose hover state is isolated
/// here. The pointer sliding across rows during a scroll then re-renders only this
/// thin background — not the wrapped `PostRowView`, whose `.equatable()` inputs are
/// unchanged, so its body is skipped. Hover previously lived as `@State` inside
/// `PostRowView`, which forced a full text re-typeset every time a row passed under
/// the cursor mid-scroll; that was a dominant scroll-time cost in Time Profiler.
struct RowHoverHighlight: ViewModifier {
    /// Whether this row is the j/k focus target (draws the leading accent bar).
    var isFocused: Bool = false
    @EnvironmentObject private var theme: ThemeStore
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isFocused || isHovered ? theme.rowHover : Color.clear)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .overlay(alignment: .leading) {
                if isFocused {
                    Rectangle().fill(theme.accent).frame(width: 3)
                }
            }
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Apply the row hover (and optional focus) highlight without letting hover
    /// changes re-render the wrapped content. See `RowHoverHighlight`.
    func rowHoverHighlight(isFocused: Bool = false) -> some View {
        modifier(RowHoverHighlight(isFocused: isFocused))
    }
}

/// Shared chrome for inline post thumbnails: rounded corners, a hairline border, a
/// tappable shape, and an accessibility label. Reused by the single-image and grid
/// thumbnails so their framing stays the only difference between them.
private struct ThumbnailChrome: ViewModifier {
    @EnvironmentObject private var theme: ThemeStore
    let alt: String
    let onTap: () -> Void

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel(alt.isEmpty ? "画像" : alt)
            .onTapGesture(perform: onTap)
    }
}
