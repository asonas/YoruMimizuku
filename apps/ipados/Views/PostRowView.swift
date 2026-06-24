import SwiftUI
import BlueskyCore
import YoruMimizukuKit

/// One timeline row on iPad, rendered to match the macOS row: a fixed-width avatar
/// column so every row's text aligns, a repost/reply context header indented to that
/// text column, themed typography and colors, and the full media set (single-image
/// 5:4 crop, image grid, video poster, link card, quote card) with a sensitive-media
/// blur curtain. Touch-first: actions are visible buttons and a context menu rather
/// than hover affordances.
struct PostRowView: View {
    let post: PostDisplay
    let density: DisplayDensity
    let now: Date
    /// Whether this row is the j/k focus target (draws a themed background + accent bar).
    var isFocused: Bool = false
    /// Whether to show the "reply to @handle" affordance. Hidden inside the
    /// conversation inspector, where the parent is already on screen.
    var showReplyMarker: Bool = true
    /// Whether the action bar is tappable. Set false where the row is itself wrapped
    /// in a button (conversation ancestors) so the counts render as plain labels.
    var interactiveActions: Bool = true
    /// Thread-grouping flags (see `FeedThreading`): when set, a member of the same
    /// reply chain sits directly above / below, and the avatar column draws the
    /// connector line toward it. Used by the feed in a later phase.
    var connectsToPrevious: Bool = false
    var connectsToNext: Bool = false
    /// Whether this row is one of the viewer's own posts, so the context menu can
    /// offer a delete action. The host decides ownership (post DID == account DID).
    var canDelete: Bool = false
    /// The feed column's measured width, injected by the feed once per layout pass.
    /// Drives the vertical/reflow decision via `TimelineLayout`. Default 0 keeps the
    /// row vertical until the first measurement arrives.
    var contentWidth: CGFloat = 0

    var onImageTap: (([URL], Int) -> Void)?
    /// Row tapped (open the conversation).
    var onOpenThread: ((PostDisplay) -> Void)?
    /// Avatar tapped (open the author tab).
    var onOpenAuthor: ((String, String, String?, URL?) -> Void)?
    /// Reply action tapped (open the reply composer).
    var onReply: ((PostDisplay) -> Void)?
    /// "引用" chosen (open the quote composer).
    var onQuote: ((PostDisplay) -> Void)?
    /// Like toggled.
    var onToggleLike: ((PostDisplay) -> Void)?
    /// "リポスト" chosen (toggle the repost).
    var onToggleRepost: ((PostDisplay) -> Void)?
    /// Quote card tapped (open the quoted post's conversation).
    var onQuoteTap: ((QuotedPost) -> Void)?
    /// Reply marker tapped (open the parent post's conversation).
    var onReplyMarkerTap: ((PostDisplay) -> Void)?
    var onCopyPermalink: ((PostDisplay) -> Void)?
    var onOpenPermalink: ((PostDisplay) -> Void)?
    /// "削除" chosen from the context menu (host confirms then removes).
    var onDelete: ((PostDisplay) -> Void)?

    @EnvironmentObject private var theme: ThemeStore
    @State private var showRepostOptions = false
    /// Whether the viewer revealed this post's sensitive media. Resets when the row
    /// leaves and re-enters the view, so a blurred post stays blurred by default.
    @State private var revealMedia = false

    private let timeFormatter = RelativeTimeFormatter()

    private var relativeTime: String {
        timeFormatter.string(for: post.createdAt, now: now)
    }

    private var avatarSize: CGFloat { density == .compact ? 24 : 42 }
    private var columnSpacing: CGFloat { density == .compact ? 8 : 11 }
    private var horizontalRowPadding: CGFloat { density == .compact ? 12 : 16 }
    private var verticalPadding: CGFloat { density == .compact ? 6 : 11 }
    private var leadingInset: CGFloat { avatarSize + columnSpacing }
    private var imageMaxWidth: CGFloat { density == .compact ? 320 : 440 }

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
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isFocused {
                Rectangle().fill(theme.accent).frame(width: 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenThread?(post) }
        .contextMenu { rowContextMenu }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isFocused { theme.rowHover } else { Color.clear }
    }

    /// The row's context menu. Always offers "リンクをコピー"; own posts also offer
    /// "削除" (destructive), which the host confirms before deleting.
    @ViewBuilder
    private var rowContextMenu: some View {
        Button {
            onCopyPermalink?(post)
        } label: {
            Label("リンクをコピー", systemImage: "link")
        }
        if canDelete {
            Divider()
            Button(role: .destructive) {
                onDelete?(post)
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    /// The avatar plus the thread connector segments. The top segment reaches back
    /// through the row's top padding to meet the previous row's line; the bottom
    /// segment stretches to the row's bottom edge so the line is continuous across
    /// grouped rows.
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
            onReplyMarkerTap?(parent)
        } label: {
            Label("@\(parent.authorHandle) への返信", systemImage: "arrowshape.turn.up.left")
                .font(.app(density == .compact ? .caption2 : .caption, weight: .medium))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
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
        .onTapGesture {
            if let did = ATURI.repo(post.id) {
                onOpenAuthor?(did, post.authorHandle, post.authorDisplayName, post.avatarURL)
            }
        }
    }

    /// Whether the post carries inline media (image or video).
    private var hasInlineMedia: Bool {
        !post.images.isEmpty || post.video != nil
    }

    /// Whether `linkCardSection` would render something.
    private var hasLinkCard: Bool {
        post.linkCard != nil
            || (post.images.isEmpty && post.video == nil && post.quote == nil && post.firstLinkURL != nil)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 2 : 4) {
            authorLine
            bodyText
            verticalMedia
            quoteSection
            actionBarSection
        }
    }

    /// Media for the vertical layout: image/video then link card.
    @ViewBuilder
    private var verticalMedia: some View {
        if hasInlineMedia {
            mediaSection(maxWidth: imageMaxWidth).padding(.top, 3)
        }
        if hasLinkCard {
            linkCardSection.padding(.top, 3)
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

    /// The quoted post card.
    @ViewBuilder
    private var quoteSection: some View {
        if let quote = post.quote {
            QuoteCardView(quote: quote, density: density, now: now) {
                onQuoteTap?(quote)
            }
            .padding(.top, 3)
        }
    }

    /// The action bar (comfortable density only): interactive or static counts.
    @ViewBuilder
    private var actionBarSection: some View {
        if density == .comfortable {
            if interactiveActions {
                actionBar
            } else {
                staticActionBar
            }
        }
    }

    private var bodyText: some View {
        Text(bodyAttributed)
            .font(.app(density == .compact ? .callout : .body))
            .foregroundStyle(theme.primaryText)
            .tint(theme.accent)
            .lineSpacing(density == .compact ? 1 : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The precomputed body with link spans tinted to the accent color.
    private var bodyAttributed: AttributedString {
        var attributed = post.bodyAttributedString
        for run in attributed.runs where run.link != nil {
            attributed[run.range].foregroundColor = theme.accent
        }
        return attributed
    }

    /// The post's attached media. When the post carries a sensitive-content label and
    /// the viewer has not revealed it, the media is blurred behind a tap-to-show
    /// overlay; tapping anywhere reveals it.
    @ViewBuilder
    private func mediaSection(maxWidth: CGFloat) -> some View {
        let media = VStack(alignment: .leading, spacing: 3) {
            if !post.images.isEmpty { imageGrid(maxWidth: maxWidth) }
            if let video = post.video {
                VideoPosterView(video: video, maxWidth: maxWidth, onTap: { onOpenPermalink?(post) })
            }
        }
        if let warning = post.mediaWarning, !revealMedia {
            media
                .blur(radius: 28)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { sensitiveMediaOverlay(warning) }
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

    /// A single attached image, capped at 5:4 (height ≤ 1.25×width): wider images show
    /// in full, taller ones are top-anchored and cropped to the cap. When a crop
    /// happens, a bottom gradient with a "全体表示" hint signals there is more.
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

    /// Bottom band shown over a tall image that was cropped to the 5:4 cap.
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

    private func thumbnail(_ image: PostImage, height: CGFloat, maxPointSize: CGFloat) -> some View {
        RemoteImage(url: image.thumbURL, maxPointSize: maxPointSize) { phase in
            imagePhaseContent(phase)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .modifier(ThumbnailChrome(alt: image.alt) { openLightbox(at: image) })
    }

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

    private func openLightbox(at image: PostImage) {
        let urls = post.images.compactMap(\.fullsizeURL)
        guard let url = image.fullsizeURL, let index = urls.firstIndex(of: url) else { return }
        onImageTap?(urls, index)
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
            Button { onReply?(post) } label: {
                actionLabel("\(post.replyCount)", systemImage: "bubble.left")
            }

            Button { showRepostOptions = true } label: {
                actionLabel("\(post.repostCount)", systemImage: "arrow.2.squarepath",
                            active: post.isReposted, activeColor: theme.accent)
            }
            .popover(isPresented: $showRepostOptions, arrowEdge: .bottom) {
                repostOptions
            }

            Button { onToggleLike?(post) } label: {
                actionLabel("\(post.likeCount)", systemImage: post.isLiked ? "heart.fill" : "heart",
                            active: post.isLiked, activeColor: theme.star)
            }

            Button { onCopyPermalink?(post) } label: {
                Image(systemName: "link")
                    .foregroundStyle(theme.tertiaryText)
            }

            Button { onOpenPermalink?(post) } label: {
                Image(systemName: "safari")
                    .foregroundStyle(theme.tertiaryText)
            }
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
                onToggleRepost?(post)
            } label: {
                Label(post.isReposted ? "リポストを取り消す" : "リポスト", systemImage: "arrow.2.squarepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            Button {
                showRepostOptions = false
                onQuote?(post)
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
        .frame(width: 220)
        .presentationCompactAdaptation(.popover)
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

    private func actionLabel(
        _ text: String, systemImage: String, active: Bool = false, activeColor: Color? = nil
    ) -> some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(active ? (activeColor ?? theme.accent) : theme.tertiaryText)
    }
}

/// Shared chrome for inline post thumbnails: rounded corners, a hairline border, a
/// tappable shape, and an accessibility label.
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

/// A circular remote avatar used in the sidebar and author header.
struct RemoteAvatar: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        RemoteImage(url: url, maxPointSize: size) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
