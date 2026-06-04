import Foundation

/// A post as shown in a timeline row. UI-framework-agnostic so it can be unit
/// tested and reused by macOS/iOS views. Real posts map into this from
/// `BlueskyCore` models in a later plan; for now `samples` provides mock data.
public struct PostDisplay: Identifiable, Equatable, Sendable {
    public let id: String
    public let authorDisplayName: String
    public let authorHandle: String
    public let body: String
    public let createdAt: Date
    public let contextLabel: String?
    public let replyCount: Int
    public let repostCount: Int
    public let likeCount: Int

    public init(
        id: String,
        authorDisplayName: String,
        authorHandle: String,
        body: String,
        createdAt: Date,
        contextLabel: String? = nil,
        replyCount: Int = 0,
        repostCount: Int = 0,
        likeCount: Int = 0
    ) {
        self.id = id
        self.authorDisplayName = authorDisplayName
        self.authorHandle = authorHandle
        self.body = body
        self.createdAt = createdAt
        self.contextLabel = contextLabel
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
