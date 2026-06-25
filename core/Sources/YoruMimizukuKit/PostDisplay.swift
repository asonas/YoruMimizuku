import Foundation
import BlueskyCore

/// The kind of sensitive-content warning that gates a post's media behind a blur
/// until the viewer chooses to reveal it. Derived from the post's content labels
/// (self-labels and labeler labels) at the display layer.
public enum MediaWarning: Equatable, Sendable {
    /// Adult / sexual content (`porn`, `sexual`, `nudity`).
    case adult
    /// Graphic or disturbing media (`graphic-media`, legacy `gore`).
    case graphic

    /// Label values that gate media as adult content.
    private static let adultValues: Set<String> = ["porn", "sexual", "nudity"]
    /// Label values that gate media as graphic content.
    private static let graphicValues: Set<String> = ["graphic-media", "gore"]

    /// Resolve the warning for a post's labels, or nil when no adult/graphic label
    /// applies. A label whose `neg` is true retracts that value, so only labels
    /// still in force count. Adult takes precedence when both apply.
    public static func from(labels: [Label]) -> MediaWarning? {
        let active = Set(labels.filter { $0.neg != true }.map(\.val))
        if !active.isDisjoint(with: adultValues) { return .adult }
        if !active.isDisjoint(with: graphicValues) { return .graphic }
        return nil
    }
}

/// An image attached to a post, ready for display: a thumbnail shown inline and a
/// full-size URL opened in the lightbox, plus alt text for accessibility.
public struct PostImage: Identifiable, Equatable, Sendable {
    public let thumbURL: URL?
    public let fullsizeURL: URL?
    public let alt: String
    /// The source image's width / height, when the embed reports it, so the row can
    /// lay the image out at its true proportions before the bytes load. Nil when the
    /// embed omits the aspect ratio.
    public let aspectRatio: Double?

    public var id: String { (fullsizeURL?.absoluteString ?? thumbURL?.absoluteString ?? "") + "|" + alt }

    public init(thumbURL: URL?, fullsizeURL: URL?, alt: String, aspectRatio: Double? = nil) {
        self.thumbURL = thumbURL
        self.fullsizeURL = fullsizeURL
        self.alt = alt
        self.aspectRatio = aspectRatio
    }
}

/// A video attached to a post, reduced to what the row renders: the poster
/// thumbnail with its aspect ratio and alt text. Playback is not inline —
/// activating the poster opens the post externally.
public struct PostVideo: Equatable, Sendable {
    public let thumbURL: URL?
    /// The HLS playlist (`.m3u8`) URL for inline playback. Nil when the embed had no
    /// usable playlist. The poster thumbnail is shown until playback starts.
    public let playlistURL: URL?
    public let alt: String?
    public let aspectRatio: Double?

    public init(thumbURL: URL?, playlistURL: URL? = nil, alt: String? = nil, aspectRatio: Double? = nil) {
        self.thumbURL = thumbURL
        self.playlistURL = playlistURL
        self.alt = alt
        self.aspectRatio = aspectRatio
    }
}

/// The quoted post inside a quote card, reduced to what the card renders: the
/// quoted author, body, timestamp, and its own media (image thumbnails and a
/// video poster). `id` is the quoted post's AT-URI, so activating the card can
/// open its conversation. A quote nested inside the quoted post is dropped.
public struct QuotedPost: Identifiable, Equatable, Sendable {
    public let id: String
    public let cid: String
    public let authorDisplayName: String
    public let authorHandle: String
    public let avatarURL: URL?
    public let body: String
    public let createdAt: Date
    public let images: [PostImage]
    public let video: PostVideo?

    public init(
        id: String,
        cid: String,
        authorDisplayName: String,
        authorHandle: String,
        avatarURL: URL? = nil,
        body: String,
        createdAt: Date,
        images: [PostImage] = [],
        video: PostVideo? = nil
    ) {
        self.id = id
        self.cid = cid
        self.authorDisplayName = authorDisplayName
        self.authorHandle = authorHandle
        self.avatarURL = avatarURL
        self.body = body
        self.createdAt = createdAt
        self.images = images
        self.video = video
    }
}

/// Reference box for a post's reply parent. A class breaks the otherwise
/// recursive value type (`PostDisplay` containing a `PostDisplay`); it is
/// immutable so it stays `Sendable`.
public final class ReplyParent: Equatable, Sendable {
    public let post: PostDisplay

    public init(_ post: PostDisplay) {
        self.post = post
    }

    public static func == (lhs: ReplyParent, rhs: ReplyParent) -> Bool {
        lhs.post == rhs.post
    }
}

/// A post as shown in a timeline row. UI-framework-agnostic so it can be unit
/// tested and reused by macOS/iOS views. Real posts map into this from
/// `BlueskyCore` models in a later plan; for now `samples` provides mock data.
public struct PostDisplay: Identifiable, Equatable, Sendable {
    public let id: String
    /// The post record's CID, needed alongside `id` (its URI) to form the
    /// `com.atproto.repo.strongRef` subject of a like / repost / quote.
    public let cid: String
    public let authorDisplayName: String
    public let authorHandle: String
    public let avatarURL: URL?
    public let body: String
    /// The body split into display spans (plain text plus tappable links,
    /// hashtags, and mentions). For mock/plain posts this is a single text span.
    public let bodySegments: [RichTextSegment]
    /// The body rendered once as an `AttributedString`: link spans carry a `.link`
    /// attribute; color is left to the view's `.tint` so this stays theme-independent.
    /// Precomputed here (not in the row's `body`) so scrolling does not rebuild it
    /// per frame — the per-render rebuild was the top self-weight leaf
    /// (`s_strFromUTF8WithSub`, UTF-8 conversion) in Time Profiler.
    public let bodyAttributedString: AttributedString
    public let createdAt: Date
    public let contextLabel: String?
    /// The sensitive-content warning gating this post's media (images / video
    /// poster) behind a blur, or nil when no adult/graphic label applies.
    public let mediaWarning: MediaWarning?
    public let images: [PostImage]
    /// The external-link preview card attached to this post, when its embed is
    /// `app.bsky.embed.external#view`. Rendered between the body/images and the
    /// action bar.
    public let linkCard: LinkCard?
    /// The video attached to this post (`app.bsky.embed.video#view`), rendered
    /// as a poster image with a play badge.
    public let video: PostVideo?
    /// The post this one quotes (`app.bsky.embed.record#view` /
    /// `recordWithMedia#view`), rendered as a bordered quote card.
    public let quote: QuotedPost?
    /// The post this one replies to, when its parent is available in the feed.
    public let replyParent: ReplyParent?
    public let replyCount: Int
    /// Counts and viewer state are `var` so an interaction can be reflected
    /// optimistically in place before the network round-trip confirms it.
    public var repostCount: Int
    public var likeCount: Int
    /// AT-URI of the viewer's own like record when they have liked this post.
    public var viewerLikeURI: String?
    /// AT-URI of the viewer's own repost record when they have reposted it.
    public var viewerRepostURI: String?

    /// The first web link in the body (link facets only — hashtags and mentions
    /// also carry URLs but are in-app destinations). Used to build an OGP preview
    /// card when the post carries no external embed of its own.
    public var firstLinkURL: URL? {
        bodySegments.first { $0.kind == .link }?.url
    }

    /// Whether the viewer has liked this post.
    public var isLiked: Bool { viewerLikeURI != nil }
    /// Whether the viewer has reposted this post.
    public var isReposted: Bool { viewerRepostURI != nil }

    public init(
        id: String,
        cid: String = "",
        authorDisplayName: String,
        authorHandle: String,
        avatarURL: URL? = nil,
        body: String,
        bodySegments: [RichTextSegment]? = nil,
        createdAt: Date,
        contextLabel: String? = nil,
        mediaWarning: MediaWarning? = nil,
        images: [PostImage] = [],
        linkCard: LinkCard? = nil,
        video: PostVideo? = nil,
        quote: QuotedPost? = nil,
        replyParent: ReplyParent? = nil,
        replyCount: Int = 0,
        repostCount: Int = 0,
        likeCount: Int = 0,
        viewerLikeURI: String? = nil,
        viewerRepostURI: String? = nil
    ) {
        self.id = id
        self.cid = cid
        self.authorDisplayName = authorDisplayName
        self.authorHandle = authorHandle
        self.avatarURL = avatarURL
        self.body = body
        let segments = bodySegments ?? RichText.segments(text: body, facets: [])
        self.bodySegments = segments
        self.bodyAttributedString = Self.attributedBody(from: segments)
        self.createdAt = createdAt
        self.contextLabel = contextLabel
        self.mediaWarning = mediaWarning
        self.images = images
        self.linkCard = linkCard
        self.video = video
        self.quote = quote
        self.replyParent = replyParent
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
        self.viewerLikeURI = viewerLikeURI
        self.viewerRepostURI = viewerRepostURI
    }

    /// Build the body's display string from its segments. Link spans carry a
    /// `.link` attribute only; the foreground color is intentionally omitted so the
    /// result is theme-independent and can be precomputed once — the view tints
    /// links via `.tint(theme.accent)`.
    static func attributedBody(from segments: [RichTextSegment]) -> AttributedString {
        segments.reduce(into: AttributedString()) { result, segment in
            var run = AttributedString(segment.text)
            if let url = segment.url { run.link = url }
            result += run
        }
    }

    /// Sentinel URIs used while a like / repost is in flight: `isLiked` /
    /// `isReposted` read true immediately, then the real record URI replaces the
    /// sentinel once the network confirms it.
    public static let pendingLikeURI = "pending:like"
    public static let pendingRepostURI = "pending:repost"

    /// Optimistically mark this post liked: flip the viewer state and bump the
    /// count. No-op if already liked so a double tap cannot double-count.
    public mutating func applyOptimisticLike() {
        guard !isLiked else { return }
        viewerLikeURI = Self.pendingLikeURI
        likeCount += 1
    }

    /// Optimistically clear the like and decrement the count (never below zero).
    public mutating func applyOptimisticUnlike() {
        guard isLiked else { return }
        viewerLikeURI = nil
        likeCount = max(0, likeCount - 1)
    }

    /// Optimistically mark this post reposted; no-op if already reposted.
    public mutating func applyOptimisticRepost() {
        guard !isReposted else { return }
        viewerRepostURI = Self.pendingRepostURI
        repostCount += 1
    }

    /// Optimistically clear the repost and decrement the count (never below zero).
    public mutating func applyOptimisticUnrepost() {
        guard isReposted else { return }
        viewerRepostURI = nil
        repostCount = max(0, repostCount - 1)
    }

    /// Deterministic mock timeline for the app shell, newest first.
    public static func samples(now: Date) -> [PostDisplay] {
        [
            PostDisplay(
                id: "p1",
                authorDisplayName: "あそなす",
                authorHandle: "asonas.bsky.social",
                body: "夜フクロウみたいなクライアントを作っている。行は詰まってる方が一覧性が高くて好き。",
                createdAt: now.addingTimeInterval(-120),
                replyCount: 3, repostCount: 12, likeCount: 48
            ),
            PostDisplay(
                id: "p2",
                authorDisplayName: "bob",
                authorHandle: "bob.bsky.social",
                body: "AT Protocol の Jetstream、思ったより素直な JSON で扱いやすい。",
                createdAt: now.addingTimeInterval(-14 * 60),
                contextLabel: "Reposted by you",
                replyCount: 1, repostCount: 5, likeCount: 20
            ),
            PostDisplay(
                id: "p3",
                authorDisplayName: "carol",
                authorHandle: "carol.bsky.social",
                body: "DPoP の nonce 再試行さえ通れば認証は山を越える。",
                createdAt: now.addingTimeInterval(-31 * 60),
                contextLabel: "Reply to @alice",
                replyCount: 0, repostCount: 1, likeCount: 7
            ),
            PostDisplay(
                id: "p4",
                authorDisplayName: "dave",
                authorHandle: "dave.bsky.social",
                body: "SwiftUI の WindowGroup で複数ウィンドウ、macOS だと相性いい。",
                createdAt: now.addingTimeInterval(-60 * 60),
                replyCount: 2, repostCount: 4, likeCount: 15
            )
        ]
    }
}
