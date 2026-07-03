import SwiftUI
import YoruMimizukuKit
#if canImport(AppKit)
import AppKit
#endif

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
    /// Called when the timestamp is tapped, so the host can open this post's
    /// conversation. Only wired where the row is interactive.
    var onOpenConversation: () -> Void = {}
    /// Called when the quote card is tapped, so the host can open the quoted
    /// post's conversation.
    var onQuoteTap: (QuotedPost) -> Void = { _ in }
    /// Whether this row is one of the viewer's own posts, so the context menu can
    /// offer a delete action. The host decides ownership (post DID == account DID).
    var canDelete: Bool = false
    /// Called when "削除" is chosen from the row's context menu, so the host can
    /// confirm and remove the post.
    var onDelete: () -> Void = {}
    /// Thread-grouping flags (see `FeedThreading`): when set, a member of the
    /// same reply chain sits directly above / below, and the avatar column draws
    /// the Bluesky-web-style connector line toward it. The reply marker is
    /// redundant when the parent is the row right above, so it is hidden.
    var connectsToPrevious: Bool = false
    var connectsToNext: Bool = false
    /// The feed column's measured width (the List row width), injected by `FeedView`
    /// once per layout pass. Drives the vertical/reflow decision via `TimelineLayout`.
    /// Default 0 keeps the row vertical until the first measurement arrives.
    var contentWidth: CGFloat = 0

    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.openURL) private var openURL
    @State private var showRepostOptions = false
    /// Whether the viewer revealed this post's sensitive media. Resets when the row
    /// leaves and re-enters the view, so a blurred post stays blurred by default.
    @State private var revealMedia = false
    /// Whether the pointer is over the timestamp, so it underlines to signal it
    /// is clickable (macOS only; the resting timestamp stays unstyled).
    @State private var isTimestampHovered = false

    private let timeFormatter = RelativeTimeFormatter()

    /// Open this post's public permalink in the default browser. Used by the
    /// video poster, whose playback is not inline in v1.
    private func openInBrowser() {
        guard let url = PostPermalink.url(for: post) else { return }
        openURL(url)
    }

    private var relativeTime: String {
        timeFormatter.string(for: post.createdAt, now: now)
    }

    private var avatarSize: CGFloat { density == .compact ? 24 : 42 }
    private var columnSpacing: CGFloat { density == .compact ? 8 : 11 }
    /// The row's horizontal padding. Single-sourced here because both the row
    /// chrome (`.padding(.horizontal:)`) and `regionWidth` depend on it; if they
    /// drift apart the reflow width math silently goes wrong.
    private var horizontalRowPadding: CGFloat { density == .compact ? 12 : 16 }
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
            && lhs.canDelete == rhs.canDelete
            && lhs.contentWidth == rhs.contentWidth
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
        .padding(.horizontal, horizontalRowPadding)
        .contextMenu { rowContextMenu }
    }

    /// The row's right-click menu. Always offers "リンクをコピー"; own posts also
    /// offer "削除" (destructive), which the host confirms before deleting.
    @ViewBuilder
    private var rowContextMenu: some View {
        Button {
            onSelect()
            onCopyLink()
        } label: {
            Label("リンクをコピー", systemImage: "link")
        }
        if canDelete {
            Divider()
            Button(role: .destructive) {
                onSelect()
                onDelete()
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
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

    /// Whether the post carries inline media (image or video). Single source for the
    /// guard repeated by `verticalMedia`, `mediaColumn`, and `hasReflowMedia`.
    private var hasInlineMedia: Bool {
        !post.images.isEmpty || post.video != nil
    }

    /// Whether `linkCardSection` would render something: the post's own link embed,
    /// or the lazy OGP fallback for a text-only post carrying a bare link. Mirrors
    /// the binding conditions inside `linkCardSection` so layout guards and the
    /// renderer can't drift apart.
    private var hasLinkCard: Bool {
        post.linkCard != nil
            || (post.images.isEmpty && post.video == nil && post.quote == nil && post.firstLinkURL != nil)
    }

    /// Whether this post has media that the reflow layout would move to the right
    /// rail. When false there is nothing to reflow, so the row stays vertical even
    /// in a wide window.
    private var hasReflowMedia: Bool {
        hasInlineMedia || hasLinkCard
    }

    @ViewBuilder
    private var content: some View {
        let region = regionWidth(forContentWidth: contentWidth)
        if TimelineLayout.placement(regionWidth: Double(region)) == .reflow && hasReflowMedia {
            // The body grows to fill the row; the media rail is pinned to the right
            // edge. The text takes whatever width is left (line length grows with the
            // window — accepted to avoid a right-hand gap), so the media never strands
            // mid-row and no trailing whitespace appears.
            HStack(alignment: .top, spacing: CGFloat(TimelineLayout.columnGap)) {
                VStack(alignment: .leading, spacing: density == .compact ? 2 : 4) {
                    authorLine
                    bodyText
                    quoteSection
                    actionBarSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                mediaColumn(maxWidth: CGFloat(TimelineLayout.mediaRailWidth))
                    .frame(width: CGFloat(TimelineLayout.mediaRailWidth), alignment: .top)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: density == .compact ? 2 : 4) {
                authorLine
                bodyText
                verticalMedia
                quoteSection
                actionBarSection
            }
        }
    }

    /// The available width for the body+media region: the row width minus the row's
    /// horizontal padding, the avatar column, and the column spacing.
    private func regionWidth(forContentWidth width: CGFloat) -> CGFloat {
        width - horizontalRowPadding * 2 - avatarSize - columnSpacing
    }

    /// Media for the narrow vertical layout: image/video then link card, with the
    /// original top paddings preserved so the stacked appearance is unchanged.
    @ViewBuilder
    private var verticalMedia: some View {
        if hasInlineMedia {
            mediaSection(maxWidth: imageMaxWidth).padding(.top, 3)
        }
        if hasLinkCard {
            linkCardSection.padding(.top, 3)
        }
    }

    /// Media for the wide reflow layout's right rail: image/video then link card,
    /// stacked at the rail width.
    @ViewBuilder
    private func mediaColumn(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasInlineMedia {
                mediaSection(maxWidth: maxWidth)
            }
            if hasLinkCard {
                linkCardSection
            }
        }
    }

    /// The post's external-link (OGP) card: the post's own embed, or a lazily resolved
    /// preview for a text-only post that carries a bare link.
    @ViewBuilder
    private var linkCardSection: some View {
        if let card = post.linkCard {
            LinkCardView(card: card, density: density)
        } else if post.images.isEmpty, post.video == nil, post.quote == nil,
                  let url = post.firstLinkURL {
            LazyLinkCardView(url: url, density: density)
        }
    }

    /// The quoted post card. Stays in the body (left) column in both layouts.
    @ViewBuilder
    private var quoteSection: some View {
        if let quote = post.quote {
            QuoteCardView(quote: quote, density: density, now: now) {
                onQuoteTap(quote)
            }
            .padding(.top, 3)
        }
    }

    /// The action bar (comfortable density only): interactive or static counts.
    @ViewBuilder
    private var actionBarSection: some View {
        if density == .comfortable {
            if interactiveActions {
                actionBar.padding(.top, 6)
            } else {
                staticActionBar.padding(.top, 6)
            }
        }
    }

    // The body's characters (the costly UTF-8 build) are precomputed on
    // `PostDisplay`; here we only re-apply the link color, which mutates run
    // attributes without rebuilding the string.
    //
    // No `.textSelection(.enabled)`: on macOS a selectable `Text` and
    // tappable `.link` runs are mutually incompatible — once the row
    // re-lays-out (e.g. focus toggling its background) the link spans render
    // blank, so URLs vanish on focus and become unclickable. Links win over
    // body selection here; the copy-link action covers sharing a post.
    private var bodyText: some View {
        Text(bodyAttributed)
            .font(.app(density == .compact ? .callout : .body))
            .foregroundStyle(theme.primaryText)
            .tint(theme.accent)
            .lineSpacing(density == .compact ? 1 : 2)
            .fixedSize(horizontal: false, vertical: true)
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

    /// The post's attached media (image grid and/or video poster). When the post
    /// carries a sensitive-content label and the viewer has not revealed it, the
    /// media is blurred behind a tap-to-show overlay; tapping anywhere reveals it.
    @ViewBuilder
    private func mediaSection(maxWidth: CGFloat) -> some View {
        let media = VStack(alignment: .leading, spacing: 3) {
            if !post.images.isEmpty { imageGrid(maxWidth: maxWidth) }
            if let video = post.video {
                VideoPosterView(video: video, maxWidth: maxWidth, onTap: openInBrowser)
            }
        }
        if let warning = post.mediaWarning, !revealMedia {
            media
                .blur(radius: 28)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { sensitiveMediaOverlay(warning) }
                // Disable the media's own taps (lightbox / video) while blurred so
                // the first tap only reveals; the overlay's gesture handles reveal.
                .allowsHitTesting(false)
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { revealMedia = true }
                }
        } else {
            media
        }
    }

    /// The "閲覧注意" curtain shown over blurred sensitive media.
    private func sensitiveMediaOverlay(_ warning: MediaWarning) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 18))
            Text(warning == .graphic ? "閲覧注意（過激なメディア）" : "閲覧注意（センシティブ）")
                .font(.app(.caption)).fontWeight(.medium)
            Text("タップで表示")
                .font(.app(.caption2)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func imageGrid(maxWidth: CGFloat) -> some View {
        // A lone image is laid out at its true aspect ratio (see `singleImage`); two
        // or more share the fixed-height cover-cropped grid where uniform tiles read
        // better than mismatched proportions.
        if post.images.count == 1, let image = post.images.first {
            singleImage(image, maxWidth: maxWidth)
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 2),
                spacing: 5
            ) {
                ForEach(post.images) { image in
                    thumbnail(image, height: 140, maxPointSize: 220)
                }
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
        }
    }

    /// A single attached image. Its display height is capped at 5:4 (height ≤ 1.25×
    /// width): wider images show in full, taller ones are top-anchored and cropped to
    /// the cap so the row never grows absurdly tall. When a crop actually happens, a
    /// bottom gradient with a "全体表示" hint signals there is more; the lightbox always
    /// shows the full image. The decode size follows the box's longer edge to stay sharp.
    private func singleImage(_ image: PostImage, maxWidth: CGFloat) -> some View {
        let natural = image.aspectRatio ?? 4.0 / 3.0
        let boxRatio = CGFloat(TimelineLayout.clampedSingleImageRatio(natural))
        let cropped = TimelineLayout.isTallCropped(natural)
        let decodeEdge = max(maxWidth, maxWidth / boxRatio)
        return Color.clear
            .aspectRatio(boxRatio, contentMode: .fit)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .overlay(alignment: .top) {
                RemoteImage(url: image.thumbURL, maxPointSize: decodeEdge) { phase in
                    imagePhaseContent(phase)
                }
            }
            .clipped()
            .overlay(alignment: .bottom) {
                if cropped { tallCropHint }
            }
            .modifier(ThumbnailChrome(alt: image.alt) { openLightbox(at: image) })
    }

    /// Bottom band shown over a tall image that was cropped to the 5:4 cap. Hit testing
    /// is disabled so a tap falls through to `ThumbnailChrome`'s lightbox gesture.
    private var tallCropHint: some View {
        HStack(spacing: 4) {
            Spacer()
            Image(systemName: "arrow.up.left.and.arrow.down.right")
            Text("全体表示")
        }
        .font(.app(.caption2))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.5)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .allowsHitTesting(false)
    }

    // Like `singleImage`, the image lives in an overlay of a fixed container:
    // `scaledToFill` reports a size larger than the proposal on one axis, so a
    // bare frame lets a grid cell outgrow its column and overlap the neighbor.
    private func thumbnail(_ image: PostImage, height: CGFloat, maxPointSize: CGFloat) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                RemoteImage(url: image.thumbURL, maxPointSize: maxPointSize) { phase in
                    imagePhaseContent(phase)
                }
            }
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

    @ViewBuilder
    private var timestampView: some View {
        // Keep the base a `Text` so `.underline(_:)` (a Text method) applies before
        // `.foregroundStyle` turns it into an opaque View.
        let base = Text(relativeTime)
            .font(.app(density == .compact ? .caption2 : .caption))
            .monospacedDigit()
            .underline(interactiveActions && isTimestampHovered)
        if interactiveActions {
            base
                .foregroundStyle(theme.tertiaryText)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect()
                    onOpenConversation()
                }
                .onHover { hovering in
                    isTimestampHovered = hovering
                    #if canImport(AppKit)
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                    #endif
                }
                .help("会話を開く")
        } else {
            base.foregroundStyle(theme.tertiaryText)
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
            timestampView
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
