import Foundation

/// Response of `app.bsky.feed.getTimeline`: a page of feed items plus an optional
/// pagination cursor. Only the fields Hoshidukiyo currently renders are modeled;
/// unknown keys in the JSON are ignored by `Decodable`.
public struct TimelineResponse: Decodable, Equatable, Sendable {
    public let feed: [FeedViewPost]
    public let cursor: String?

    public init(feed: [FeedViewPost], cursor: String?) {
        self.feed = feed
        self.cursor = cursor
    }
}

/// One row in a feed: the post itself plus an optional `reason` (e.g. a repost
/// that surfaced the post into this timeline).
public struct FeedViewPost: Decodable, Equatable, Sendable {
    public let post: PostView
    public let reason: ReasonRepost?

    public init(post: PostView, reason: ReasonRepost? = nil) {
        self.post = post
        self.reason = reason
    }
}

/// A hydrated post (`app.bsky.feed.defs#postView`).
public struct PostView: Decodable, Equatable, Sendable {
    public let uri: String
    public let cid: String
    public let author: ProfileViewBasic
    public let record: PostRecord
    public let replyCount: Int?
    public let repostCount: Int?
    public let likeCount: Int?
    public let indexedAt: String

    public init(
        uri: String,
        cid: String,
        author: ProfileViewBasic,
        record: PostRecord,
        replyCount: Int?,
        repostCount: Int?,
        likeCount: Int?,
        indexedAt: String
    ) {
        self.uri = uri
        self.cid = cid
        self.author = author
        self.record = record
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
        self.indexedAt = indexedAt
    }
}

/// A minimal author profile (`app.bsky.actor.defs#profileViewBasic`).
public struct ProfileViewBasic: Decodable, Equatable, Sendable {
    public let did: String
    public let handle: String
    public let displayName: String?
    public let avatar: String?

    public init(did: String, handle: String, displayName: String?, avatar: String?) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.avatar = avatar
    }
}

/// The post record (`app.bsky.feed.post`). Only text and createdAt are modeled
/// for now; `createdAt` stays a string and is parsed at the display layer.
public struct PostRecord: Decodable, Equatable, Sendable {
    public let text: String
    public let createdAt: String

    public init(text: String, createdAt: String) {
        self.text = text
        self.createdAt = createdAt
    }
}

/// The repost reason (`app.bsky.feed.defs#reasonRepost`) attached to a feed item
/// when the post appears because someone the viewer follows reposted it.
public struct ReasonRepost: Decodable, Equatable, Sendable {
    public let by: ProfileViewBasic
    public let indexedAt: String

    public init(by: ProfileViewBasic, indexedAt: String) {
        self.by = by
        self.indexedAt = indexedAt
    }
}
