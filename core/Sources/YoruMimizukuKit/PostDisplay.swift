import Foundation

/// An image attached to a post, ready for display: a thumbnail shown inline and a
/// full-size URL opened in the lightbox, plus alt text for accessibility.
public struct PostImage: Identifiable, Equatable, Sendable {
    public let thumbURL: URL?
    public let fullsizeURL: URL?
    public let alt: String

    public var id: String { (fullsizeURL?.absoluteString ?? thumbURL?.absoluteString ?? "") + "|" + alt }

    public init(thumbURL: URL?, fullsizeURL: URL?, alt: String) {
        self.thumbURL = thumbURL
        self.fullsizeURL = fullsizeURL
        self.alt = alt
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
    public let authorDisplayName: String
    public let authorHandle: String
    public let avatarURL: URL?
    public let body: String
    /// The body split into display spans (plain text plus tappable links,
    /// hashtags, and mentions). For mock/plain posts this is a single text span.
    public let bodySegments: [RichTextSegment]
    public let createdAt: Date
    public let contextLabel: String?
    public let images: [PostImage]
    /// The post this one replies to, when its parent is available in the feed.
    public let replyParent: ReplyParent?
    public let replyCount: Int
    public let repostCount: Int
    public let likeCount: Int

    public init(
        id: String,
        authorDisplayName: String,
        authorHandle: String,
        avatarURL: URL? = nil,
        body: String,
        bodySegments: [RichTextSegment]? = nil,
        createdAt: Date,
        contextLabel: String? = nil,
        images: [PostImage] = [],
        replyParent: ReplyParent? = nil,
        replyCount: Int = 0,
        repostCount: Int = 0,
        likeCount: Int = 0
    ) {
        self.id = id
        self.authorDisplayName = authorDisplayName
        self.authorHandle = authorHandle
        self.avatarURL = avatarURL
        self.body = body
        self.bodySegments = bodySegments ?? RichText.segments(text: body, facets: [])
        self.createdAt = createdAt
        self.contextLabel = contextLabel
        self.images = images
        self.replyParent = replyParent
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
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
