import Foundation

/// Response of `app.bsky.feed.getTimeline`: a page of feed items plus an optional
/// pagination cursor. Only the fields YoruMimizuku currently renders are modeled;
/// unknown keys in the JSON are ignored by `Decodable`.
public struct TimelineResponse: Decodable, Equatable, Sendable {
    public let feed: [FeedViewPost]
    public let cursor: String?

    public init(feed: [FeedViewPost], cursor: String?) {
        self.feed = feed
        self.cursor = cursor
    }
}

/// One row in a feed: the post itself, an optional `reason` (e.g. a repost that
/// surfaced the post), and an optional `reply` reference to the post it answers.
public struct FeedViewPost: Decodable, Equatable, Sendable {
    public let post: PostView
    public let reason: ReasonRepost?
    public let reply: ReplyRef?

    public init(post: PostView, reason: ReasonRepost? = nil, reply: ReplyRef? = nil) {
        self.post = post
        self.reason = reason
        self.reply = reply
    }
}

/// The reply context (`app.bsky.feed.defs#replyRef`). Only the hydrated immediate
/// `parent` post is modeled; if the parent is not a viewable post (notFound /
/// blocked) it decodes to nil so a missing parent never breaks the feed.
public struct ReplyRef: Decodable, Equatable, Sendable {
    public let parent: PostView?

    public init(parent: PostView?) {
        self.parent = parent
    }

    enum CodingKeys: String, CodingKey { case parent }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.parent = try? container.decodeIfPresent(PostView.self, forKey: .parent)
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
    public let embed: PostEmbed?

    public init(
        uri: String,
        cid: String,
        author: ProfileViewBasic,
        record: PostRecord,
        replyCount: Int?,
        repostCount: Int?,
        likeCount: Int?,
        indexedAt: String,
        embed: PostEmbed? = nil
    ) {
        self.uri = uri
        self.cid = cid
        self.author = author
        self.record = record
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
        self.indexedAt = indexedAt
        self.embed = embed
    }
}

/// The post's view embed. Only `app.bsky.embed.images#view` is modeled; for any
/// other embed kind (external, record, video, recordWithMedia) `images` is empty
/// so decoding never fails on shapes we do not render yet.
public struct PostEmbed: Decodable, Equatable, Sendable {
    public let images: [EmbedImage]

    public init(images: [EmbedImage]) {
        self.images = images
    }

    enum CodingKeys: String, CodingKey { case images }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.images = (try? container.decode([EmbedImage].self, forKey: .images)) ?? []
    }
}

/// One image in an `app.bsky.embed.images#view`: a thumbnail and full-size URL
/// plus its alt text.
public struct EmbedImage: Decodable, Equatable, Sendable {
    public let thumb: String
    public let fullsize: String
    public let alt: String

    public init(thumb: String, fullsize: String, alt: String) {
        self.thumb = thumb
        self.fullsize = fullsize
        self.alt = alt
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
