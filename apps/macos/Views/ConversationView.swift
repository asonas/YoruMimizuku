import SwiftUI
import AppKit
import YoruMimizukuKit

/// The detail pane's スレッド tab, as in the desktop prototype: the ancestors as
/// compact rows (each re-anchors the pane), the anchor post at full size with its
/// media, link card, quote and counts, then the reply tree indented 20pt per
/// level with a connector line and a fold control on replies that have replies.
struct ConversationView: View {
    @ObservedObject var model: ThreadViewModel
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var toastCenter: ToastCenter

    let now: Date
    var onImageTap: ([URL], Int) -> Void
    var onOpenConversation: (PostDisplay) -> Void
    var onOpenAuthor: (PostDisplay) -> Void = { _ in }
    /// Opens the conversation of a tapped quoted post.
    var onOpenQuote: (QuotedPost) -> Void = { _ in }
    /// Opens the reply composer for the anchor.
    var onReply: (PostDisplay) -> Void = { _ in }

    /// Replies whose subtree the reader folded.
    @State private var folded: Set<String> = []
    /// Whether the reader revealed the anchor's labeled media.
    @State private var revealMedia = false

    private static let timeFormatter = RelativeTimeFormatter(style: .japanese)

    var body: some View {
        content
            .background(theme.canvas)
            // A page shown again while its previous load is still winding down
            // (the pane was left mid-load) starts a fresh load; the model drops
            // the older one's late result.
            .task {
                switch model.state {
                case .idle, .loading: await model.load()
                case .loaded, .failed: break
                }
            }
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
        case let .loaded(thread):
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ancestors(of: thread.focus)) { ancestor in
                        compactRow(ancestor, depth: 0, hasReplies: true, help: "この投稿を中心に会話を開く")
                    }
                    anchor(thread.focus)
                    Rectangle().fill(theme.divider).frame(height: 1)
                    replies(thread.replies)
                }
                .padding(.bottom, 12)
            }
        }
    }

    /// Oldest (thread root) first, so they read down to the anchor.
    private func ancestors(of focus: PostDisplay) -> [PostDisplay] {
        var chain: [PostDisplay] = []
        var current = focus.replyParent?.post
        while let post = current {
            chain.append(post)
            current = post.replyParent?.post
        }
        return chain.reversed()
    }

    // MARK: - Anchor

    private func anchor(_ post: PostDisplay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { onOpenAuthor(post) } label: { avatar(post.avatarURL, size: 38) }
                    .buttonStyle(.plain)
                    .help("@\(post.authorHandle) のページを開く")
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(post.authorDisplayName)
                            .font(.appSize(14, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                        verifiedMark(post)
                    }
                    Text("@\(post.authorHandle) ・ \(Self.timeFormatter.string(for: post.createdAt, now: now))")
                        .font(.appSize(12))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            if !post.body.isEmpty {
                Text(post.bodyAttributedString)
                    .font(.appSize(15.5))
                    .lineSpacing(15.5 * 0.55)
                    .foregroundStyle(theme.primaryText)
                    .tint(theme.accent)
                    // No .textSelection here: with link attributes it blanks
                    // links after a relayout (see PostRowView).
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let warning = post.mediaWarning, post.hasMedia {
                contentWarning(warning)
            }
            if post.mediaWarning == nil || revealMedia {
                media(post)
            }
            if let card = post.linkCard {
                LinkCardView(card: card, density: .comfortable)
            } else if !post.hasMedia, post.quote == nil, let url = post.firstLinkURL {
                LazyLinkCardView(url: url, density: .comfortable)
            }
            if let quote = post.quote {
                quoteBox(quote)
            }
            stats(post)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private func contentWarning(_ warning: MediaWarning) -> some View {
        HStack(spacing: 8) {
            Text(warning == .graphic ? "閲覧注意（過激なメディア）" : "閲覧注意（センシティブ）")
                .font(.appSize(12.5, weight: .bold))
            Spacer(minLength: 0)
            Button(revealMedia ? "隠す" : "表示する") { revealMedia.toggle() }
        }
        .foregroundStyle(theme.warn)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.warnTint, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func media(_ post: PostDisplay) -> some View {
        let urls = post.images.compactMap(\.fullsizeURL)
        ForEach(Array(post.images.enumerated()), id: \.offset) { index, image in
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if image.fullsizeURL != nil {
                        onImageTap(urls, post.images.prefix(index).filter { $0.fullsizeURL != nil }.count)
                    }
                } label: {
                    RemoteImage(url: image.fullsizeURL ?? image.thumbURL, maxPointSize: 900) { phase in
                        if case let .success(loaded) = phase {
                            loaded.resizable().scaledToFit()
                        } else {
                            theme.avatarPlaceholder.aspectRatio(CGFloat(image.aspectRatio ?? 1.6), contentMode: .fit)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(image.alt.isEmpty ? "画像 \(index + 1)" : image.alt)
                if !image.alt.isEmpty {
                    Text(image.alt)
                        .font(.appSize(12.5))
                        .foregroundStyle(theme.secondaryText)
                        .textSelection(.enabled)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(theme.divider).frame(width: 2) }
                }
            }
        }
        if let video = post.video {
            VideoPosterView(video: video, maxWidth: 600) {
                if let url = PostPermalink.url(for: post) { NSWorkspace.shared.open(url) }
            }
        }
    }

    /// The prototype's quote box. The quoted post's labels are not carried here,
    /// so its media stays behind the quote's own page; the box says it has some.
    private func quoteBox(_ quote: QuotedPost) -> some View {
        Button { onOpenQuote(quote) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(quote.authorDisplayName).font(.appSize(13, weight: .semibold)).foregroundStyle(theme.primaryText)
                    Text("@\(quote.authorHandle)").font(.appSize(12)).foregroundStyle(theme.tertiaryText)
                }
                if !quote.body.isEmpty {
                    Text(quote.body)
                        .font(.appSize(13.5))
                        .foregroundStyle(theme.primaryText)
                        .multilineTextAlignment(.leading)
                }
                if !quote.images.isEmpty || quote.video != nil {
                    Label(quote.video != nil ? "動画あり" : "画像 \(quote.images.count) 枚", systemImage: "photo")
                        .font(.appSize(11.5))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.divider, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("引用元を開く")
    }

    /// The prototype's counts row; the counts double as the actions.
    private func stats(_ post: PostDisplay) -> some View {
        HStack(spacing: 18) {
            Button { onReply(post) } label: { stat("bubble.left", post.replyCount, color: nil) }
                .help("返信")
            Button { Task { await model.toggleRepost(post) } } label: {
                stat("arrow.2.squarepath", post.repostCount, color: post.isReposted ? theme.repost : nil)
            }
            .help(post.isReposted ? "リポストを取り消す" : "リポスト")
            Button { Task { await model.toggleLike(post) } } label: {
                stat(post.isLiked ? "heart.fill" : "heart", post.likeCount, color: post.isLiked ? theme.like : nil)
            }
            .help(post.isLiked ? "いいねを取り消す" : "いいね")
            Button { copyPermalink(post) } label: { Image(systemName: "link").font(.system(size: 12)) }
                .foregroundStyle(theme.tertiaryText)
                .help("リンクをコピー")
        }
        .buttonStyle(.plain)
    }

    private func stat(_ systemImage: String, _ count: Int, color: Color?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.system(size: 12)).foregroundStyle(color ?? theme.tertiaryText)
            Text("\(count)").font(.appSize(12, weight: .bold).monospacedDigit()).foregroundStyle(color ?? theme.primaryText)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Replies

    /// Returns `AnyView` to break the recursive opaque-type cycle of a
    /// self-calling view builder.
    private func replies(_ nodes: [ThreadNode]) -> AnyView {
        AnyView(
            ForEach(nodes) { node in
                compactRow(
                    node.post, depth: node.depth, hasReplies: !node.replies.isEmpty && !folded.contains(node.id),
                    help: "この返信を中心に会話を開く", fold: node.replies.isEmpty ? nil : foldControl(node)
                )
                if node.replies.isEmpty, node.post.replyCount > 0 {
                    // Cut at the depth limit: re-anchoring loads the rest.
                    Button("さらに表示") { onOpenConversation(node.post) }
                        .buttonStyle(.plain)
                        .font(.appSize(11.5))
                        .foregroundStyle(theme.accent)
                        .padding(.leading, 16 + CGFloat(node.depth + 1) * 20 + 34)
                        .padding(.bottom, 6)
                } else if !folded.contains(node.id) {
                    replies(node.replies)
                }
            }
        )
    }

    private func foldControl(_ node: ThreadNode) -> AnyView {
        let isFolded = folded.contains(node.id)
        return AnyView(
            Button {
                if isFolded { folded.remove(node.id) } else { folded.insert(node.id) }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isFolded ? 0 : 90))
                    if isFolded { Text("\(count(node))") }
                }
                .font(.appSize(11.5))
                .foregroundStyle(theme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFolded ? "返信を表示" : "返信をたたむ")
        )
    }

    private func count(_ node: ThreadNode) -> Int {
        node.replies.reduce(0) { $0 + 1 + count($1) }
    }

    /// A reply (or ancestor) row: a 24pt avatar, name, handle and text, inset by
    /// depth, with the connector line running down when it has visible replies.
    private func compactRow(
        _ post: PostDisplay, depth: Int, hasReplies: Bool, help: String, fold: AnyView? = nil
    ) -> some View {
        Button { onOpenConversation(post) } label: {
            HStack(alignment: .top, spacing: 10) {
                Button { onOpenAuthor(post) } label: { avatar(post.avatarURL, size: 24) }
                    .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(post.authorDisplayName)
                            .font(.appSize(13, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                        verifiedMark(post)
                        Text("@\(post.authorHandle)")
                            .font(.appSize(12))
                            .foregroundStyle(theme.tertiaryText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Self.timeFormatter.string(for: post.createdAt, now: now))
                            .font(.appSize(12).monospacedDigit())
                            .foregroundStyle(theme.tertiaryText)
                    }
                    if !post.body.isEmpty {
                        Text(post.bodyAttributedString)
                            .font(.appSize(13.5))
                            .foregroundStyle(theme.primaryText)
                            .tint(theme.accent)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let fold { fold }
                }
            }
            .padding(.vertical, 10)
            .padding(.trailing, 16)
            .padding(.leading, 16 + CGFloat(depth) * 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) {
                if hasReplies {
                    Rectangle()
                        .fill(theme.divider)
                        .frame(width: 1.5)
                        .padding(.top, 38)
                        .padding(.leading, 16 + CGFloat(depth) * 20 + 11)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .rowHoverHighlight()
    }

    // MARK: - Shared parts

    private func avatar(_ url: URL?, size: CGFloat) -> some View {
        RemoteImage(url: url, maxPointSize: size) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                theme.avatarPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    @ViewBuilder
    private func verifiedMark(_ post: PostDisplay) -> some View {
        if post.authorIsVerified {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11))
                .foregroundStyle(theme.proto)
                .accessibilityLabel("認証済み")
        }
    }

    private func copyPermalink(_ post: PostDisplay) {
        guard let url = PostPermalink.url(for: post) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
        toastCenter.show("リンクをコピーしました")
    }

    private func stateMessage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 10) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 60)
    }
}

private extension PostDisplay {
    var hasMedia: Bool { !images.isEmpty || video != nil }
}
