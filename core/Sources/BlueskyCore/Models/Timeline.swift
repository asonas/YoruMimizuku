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

/// The post record (`app.bsky.feed.post`). `createdAt` stays a string and is
/// parsed at the display layer. `facets` carries the rich-text ranges (links,
/// hashtags, mentions) so the display layer can render them as tappable spans.
public struct PostRecord: Decodable, Equatable, Sendable {
    public let text: String
    public let createdAt: String
    public let facets: [Facet]

    public init(text: String, createdAt: String, facets: [Facet] = []) {
        self.text = text
        self.createdAt = createdAt
        self.facets = facets
    }

    enum CodingKeys: String, CodingKey {
        case text
        case createdAt
        case facets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decode(String.self, forKey: .text)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
        self.facets = (try? container.decodeIfPresent([Facet].self, forKey: .facets)) ?? []
    }
}

/// A rich-text range (`app.bsky.richtext.facet`). `byteStart` / `byteEnd` are
/// UTF-8 byte offsets into the post text (NOT character offsets); the display
/// layer must slice the UTF-8 view to map them back to a substring.
public struct Facet: Decodable, Equatable, Sendable {
    public let byteStart: Int
    public let byteEnd: Int
    public let features: [FacetFeature]

    public init(byteStart: Int, byteEnd: Int, features: [FacetFeature]) {
        self.byteStart = byteStart
        self.byteEnd = byteEnd
        self.features = features
    }

    enum CodingKeys: String, CodingKey { case index, features }
    enum IndexKeys: String, CodingKey { case byteStart, byteEnd }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let index = try container.nestedContainer(keyedBy: IndexKeys.self, forKey: .index)
        self.byteStart = try index.decode(Int.self, forKey: .byteStart)
        self.byteEnd = try index.decode(Int.self, forKey: .byteEnd)
        let boxes = (try? container.decode([FacetFeatureBox].self, forKey: .features)) ?? []
        self.features = boxes.compactMap(\.feature)
    }
}

/// Wrapper that decodes a facet feature tolerantly: an unknown `$type` yields a
/// nil `feature` rather than throwing, so one unsupported entry never discards
/// its siblings or fails the whole facet.
private struct FacetFeatureBox: Decodable {
    let feature: FacetFeature?

    init(from decoder: Decoder) throws {
        self.feature = try? FacetFeature(from: decoder)
    }
}

/// A single feature within a facet. Unknown / future feature types decode to
/// `nil` and are dropped, so a new lexicon feature never breaks decoding.
public enum FacetFeature: Decodable, Equatable, Sendable {
    case link(uri: String)
    case mention(did: String)
    case tag(tag: String)

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case uri, did, tag
    }

    /// Decoding container that tolerates unknown feature types by representing
    /// them as nil (filtered out of the parent array).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "app.bsky.richtext.facet#link":
            self = .link(uri: try container.decode(String.self, forKey: .uri))
        case "app.bsky.richtext.facet#mention":
            self = .mention(did: try container.decode(String.self, forKey: .did))
        case "app.bsky.richtext.facet#tag":
            self = .tag(tag: try container.decode(String.self, forKey: .tag))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unsupported facet feature: \(type)"
            )
        }
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
