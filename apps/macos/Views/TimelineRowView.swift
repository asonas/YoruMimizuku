import SwiftUI
import BlueskyCore
import YoruMimizukuKit

/// A post in a timeline list, as in the desktop prototype: a 32pt avatar beside
/// one column of why-line (repost / reply), header (name, verification check,
/// handle, time), body clamped to four lines, small media thumbnails, tags
/// (sensitive media, quote) and the reaction counts. Full media, link cards and
/// quoted posts are read in the detail pane.
struct TimelineRowView: View, @MainActor Equatable {
    let post: PostDisplay
    let now: Date
    var showsCounts: Bool = true
    var canDelete: Bool = false
    var onImageTap: ([URL], Int) -> Void = { _, _ in }
    var onSelect: () -> Void = {}
    /// Selects the row and opens it in the detail pane (a click on its text).
    var onActivate: () -> Void = {}
    var onReply: () -> Void = {}
    var onRepost: () -> Void = {}
    var onQuote: () -> Void = {}
    var onLike: () -> Void = {}
    var onAvatarTap: () -> Void = {}
    var onQuoteTap: (QuotedPost) -> Void = { _ in }
    var onCopyLink: () -> Void = {}
    var onMute: () -> Void = {}
    var onDelete: () -> Void = {}

    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.openURL) private var openURL
    @Environment(\.listMembership) private var listMembership
    @State private var showRepostOptions = false

    private static let avatarSize: CGFloat = 32
    private static let timeFormatter = RelativeTimeFormatter(style: .japanese)

    /// Compares the value inputs that change what is drawn (see `PostRowView`):
    /// a post's id keys its immutable content, so only the mutable counts and
    /// viewer state are compared; closures are excluded on purpose.
    static func == (lhs: TimelineRowView, rhs: TimelineRowView) -> Bool {
        lhs.post.id == rhs.post.id
            && lhs.post.replyCount == rhs.post.replyCount
            && lhs.post.repostCount == rhs.post.repostCount
            && lhs.post.likeCount == rhs.post.likeCount
            && lhs.post.viewerLikeURI == rhs.post.viewerLikeURI
            && lhs.post.viewerRepostURI == rhs.post.viewerRepostURI
            && lhs.post.mediaWarning == rhs.post.mediaWarning
            && lhs.post.authorIsVerified == rhs.post.authorIsVerified
            && lhs.post.contextLabel == rhs.post.contextLabel
            && lhs.now == rhs.now
            && lhs.showsCounts == rhs.showsCounts
            && lhs.canDelete == rhs.canDelete
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Group {
                    whyLine
                    header
                }
                .simultaneousGesture(TapGesture().onEnded { onActivate() })
                Text(post.bodyAttributedString)
                    .font(.app(.body))
                    .lineSpacing(AppTypography.pointSize(.body) * CGFloat(DesignMetrics.bodyLineSpacingRatio(.comfortable)))
                    .foregroundStyle(theme.primaryText)
                    .tint(theme.accent)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(post.body.isEmpty ? 0 : 1)
                    .frame(height: post.body.isEmpty ? 0 : nil)
                    // Text takes the click before the row's background does; a
                    // simultaneous tap keeps link clicks working and still selects.
                    .simultaneousGesture(TapGesture().onEnded { onActivate() })
                thumbnails
                tags
                reactions
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .contextMenu { contextMenu }
        .modifier(ListMembershipPrefetch(context: listMembership, authorDID: ATURI.repo(post.id)))
    }

    // MARK: - Parts

    private var avatar: some View {
        Button(action: onAvatarTap) {
            RemoteImage(url: post.avatarURL, maxPointSize: Self.avatarSize) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    theme.avatarPlaceholder
                }
            }
            .frame(width: Self.avatarSize, height: Self.avatarSize)
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(AuthorDragSource(post: post))
        .accessibilityLabel("@\(post.authorHandle) のプロフィール")
        .help("@\(post.authorHandle) のページを開く")
    }

    /// "〜がリポスト" from the feed, else "@x への返信" for a reply.
    @ViewBuilder
    private var whyLine: some View {
        if let context = post.contextLabel {
            whyLabel(context, systemImage: "arrow.2.squarepath")
        } else if let parent = post.replyParent?.post {
            whyLabel("@\(parent.authorHandle) への返信", systemImage: "arrowshape.turn.up.left")
        }
    }

    private func whyLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.appSize(11))
            .foregroundStyle(theme.tertiaryText)
            .lineLimit(1)
            .labelStyle(.titleAndIcon)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(post.authorDisplayName)
                .font(.appSize(13, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
            if post.authorIsVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.proto)
                    .accessibilityLabel("認証済み")
            }
            Text("@\(post.authorHandle)")
                .font(.appSize(12))
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Spacer(minLength: 4)
            Text(Self.timeFormatter.string(for: post.createdAt, now: now))
                .font(.appSize(12).monospacedDigit())
                .foregroundStyle(theme.tertiaryText)
                .help(post.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    /// Small thumbnails; sensitive media is not shown here (its tag says why).
    @ViewBuilder
    private var thumbnails: some View {
        if post.mediaWarning == nil, !post.images.isEmpty || post.video != nil {
            HStack(spacing: 6) {
                ForEach(Array(post.images.prefix(4).enumerated()), id: \.offset) { index, image in
                    Button {
                        onSelect()
                        // Position among the images actually handed over (those with
                        // a full-size URL), so a missing or repeated URL does not
                        // shift the start.
                        let urls = post.images.compactMap(\.fullsizeURL)
                        if image.fullsizeURL != nil {
                            let start = post.images.prefix(index).filter { $0.fullsizeURL != nil }.count
                            onImageTap(urls, start)
                        }
                    } label: {
                        thumbnail(image.thumbURL, alt: image.alt.isEmpty ? nil : "ALT")
                    }
                    .buttonStyle(.plain)
                    .help(image.alt.isEmpty ? "画像" : image.alt)
                    .accessibilityLabel(image.alt.isEmpty ? "画像 \(index + 1)" : image.alt)
                }
                if let video = post.video {
                    thumbnail(video.thumbURL, alt: nil)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        .accessibilityLabel("動画")
                }
            }
            .padding(.top, 3)
        }
    }

    private func thumbnail(_ url: URL?, alt: String?) -> some View {
        RemoteImage(url: url, maxPointSize: 64) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                theme.avatarPlaceholder
            }
        }
        .frame(width: 64, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.hairline, lineWidth: 0.5))
        .overlay(alignment: .bottomLeading) {
            if let alt {
                Text(alt)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 2))
                    .padding(3)
            }
        }
    }

    @ViewBuilder
    private var tags: some View {
        if post.mediaWarning != nil || post.quote != nil {
            HStack(spacing: 6) {
                if let warning = post.mediaWarning {
                    tag(warning == .graphic ? "閲覧注意（過激なメディア）" : "閲覧注意（センシティブ）",
                        foreground: theme.warn, background: theme.warnTint)
                        .help("ラベルが付いたメディアです。右の欄で表示できます。")
                }
                if let quote = post.quote {
                    Button {
                        onSelect()
                        onQuoteTap(quote)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "quote.opening").font(.system(size: 9))
                            Text(quote.authorDisplayName).lineLimit(1)
                        }
                        .font(.appSize(11.5))
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, 6)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("引用元を開く")
                }
            }
            .padding(.top, 3)
        }
    }

    private func tag(_ text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(.appSize(11.5))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 4))
    }

    private var reactions: some View {
        HStack(spacing: 16) {
            Button { onSelect(); onReply() } label: {
                reaction("bubble.left", count: post.replyCount, color: nil)
            }
            .help("返信")
            .accessibilityLabel(spoken("返信", post.replyCount))

            Button { onSelect(); showRepostOptions = true } label: {
                reaction("arrow.2.squarepath", count: post.repostCount, color: post.isReposted ? theme.repost : nil)
            }
            .help(post.isReposted ? "リポスト済み" : "リポスト / 引用")
            .accessibilityLabel(spoken(post.isReposted ? "リポスト済み" : "リポスト", post.repostCount))
            .popover(isPresented: $showRepostOptions, arrowEdge: .bottom) { repostOptions }

            Button { onSelect(); onLike() } label: {
                reaction(post.isLiked ? "heart.fill" : "heart", count: post.likeCount, color: post.isLiked ? theme.like : nil)
            }
            .help(post.isLiked ? "いいねを取り消す" : "いいね")
            .accessibilityLabel(spoken(post.isLiked ? "いいね済み" : "いいね", post.likeCount))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    /// VoiceOver names the count only where the row shows it.
    private func spoken(_ name: String, _ count: Int) -> String {
        showsCounts && count > 0 ? "\(name) \(count)件" : name
    }

    private func reaction(_ systemImage: String, count: Int, color: Color?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 11))
            if showsCounts, count > 0 {
                Text("\(count)").font(.appSize(11.5).monospacedDigit())
            }
        }
        .foregroundStyle(color ?? theme.tertiaryText)
        .contentShape(Rectangle())
    }

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
                Label("引用して投稿", systemImage: "quote.bubble")
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

    @ViewBuilder
    private var contextMenu: some View {
        Button("返信") { onSelect(); onReply() }
        Button(post.isReposted ? "リポストを取り消す" : "リポスト") { onSelect(); onRepost() }
        Button("引用して投稿") { onSelect(); onQuote() }
        Button(post.isLiked ? "いいねを取り消す" : "いいね") { onSelect(); onLike() }
        Divider()
        Button("リンクをコピー") { onSelect(); onCopyLink() }
        Button("ブラウザで開く") {
            onSelect()
            if let url = PostPermalink.url(for: post) { openURL(url) }
        }
        if let listMembership, let authorDID = ATURI.repo(post.id) {
            Divider()
            ListMembershipMenu(context: listMembership, actorDID: authorDID, handle: post.authorHandle)
        }
        if canDelete {
            Divider()
            Button("削除", role: .destructive) { onSelect(); onDelete() }
        } else {
            Button("この人をミュート") { onSelect(); onMute() }
        }
    }
}
