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

/// A content label (`com.atproto.label.defs#label`) attached to a post view.
/// `val` is the label value (e.g. `porn`, `sexual`, `nudity`, `graphic-media`);
/// `src` is the labeler (or author, for self-labels) DID; `neg` is true when the
/// label retracts a previously applied one. Self-labels declared on the post
/// record are surfaced here by the appview with `src` set to the author's DID.
public struct Label: Decodable, Equatable, Sendable {
    public let val: String
    public let src: String?
    public let neg: Bool?

    public init(val: String, src: String? = nil, neg: Bool? = nil) {
        self.val = val
        self.src = src
        self.neg = neg
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
    /// The viewer's own interaction state for this post: the AT-URIs of the
    /// viewer's like / repost records when they have liked / reposted it. nil
    /// (or absent fields) means the viewer has not interacted.
    public let viewer: PostViewerState?
    /// Content labels on this post (self-labels + labeler labels). Empty when the
    /// post carries none. Drives the sensitive-media warning at the display layer.
    public let labels: [Label]

    public init(
        uri: String,
        cid: String,
        author: ProfileViewBasic,
        record: PostRecord,
        replyCount: Int?,
        repostCount: Int?,
        likeCount: Int?,
        indexedAt: String,
        embed: PostEmbed? = nil,
        viewer: PostViewerState? = nil,
        labels: [Label] = []
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
        self.viewer = viewer
        self.labels = labels
    }

    enum CodingKeys: String, CodingKey {
        case uri, cid, author, record, replyCount, repostCount, likeCount, indexedAt, embed, viewer, labels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.uri = try container.decode(String.self, forKey: .uri)
        self.cid = try container.decode(String.self, forKey: .cid)
        self.author = try container.decode(ProfileViewBasic.self, forKey: .author)
        self.record = try container.decode(PostRecord.self, forKey: .record)
        self.replyCount = try container.decodeIfPresent(Int.self, forKey: .replyCount)
        self.repostCount = try container.decodeIfPresent(Int.self, forKey: .repostCount)
        self.likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount)
        self.indexedAt = try container.decode(String.self, forKey: .indexedAt)
        self.embed = try container.decodeIfPresent(PostEmbed.self, forKey: .embed)
        self.viewer = try container.decodeIfPresent(PostViewerState.self, forKey: .viewer)
        self.labels = (try? container.decodeIfPresent([Label].self, forKey: .labels)) ?? []
    }
}

/// The viewer's interaction state (`app.bsky.feed.defs#viewerState`). `like` and
/// `repost` carry the AT-URI of the viewer's own like / repost record when set,
/// so the client can show the filled state and delete the record to undo it.
public struct PostViewerState: Decodable, Equatable, Sendable {
    public let like: String?
    public let repost: String?

    public init(like: String?, repost: String?) {
        self.like = like
        self.repost = repost
    }
}

/// The post's view embed, decoded by key shape rather than `$type` so one
/// struct covers every kind we render: `app.bsky.embed.images#view` fills
/// `images`, `app.bsky.embed.external#view` fills `external`, and
/// `app.bsky.embed.video#view` (recognized by its `playlist` key) fills
/// `video`. Any embed kind we do not render decodes to an empty value so
/// decoding never fails on unknown shapes.
public struct PostEmbed: Decodable, Equatable, Sendable {
    public let images: [EmbedImage]
    public let external: EmbedExternal?
    public let video: EmbedVideo?
    public let record: EmbedRecord?

    public init(images: [EmbedImage], external: EmbedExternal? = nil, video: EmbedVideo? = nil, record: EmbedRecord? = nil) {
        self.images = images
        self.external = external
        self.video = video
        self.record = record
    }

    enum CodingKeys: String, CodingKey { case images, external, playlist, record, media }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `app.bsky.embed.recordWithMedia#view` nests its media embed (images /
        // external / video view) under `media`; decoding it as a `PostEmbed` of
        // its own lets the merge below reuse every shape this struct handles.
        let media = try? container.decodeIfPresent(PostEmbed.self, forKey: .media)
        self.images = (try? container.decode([EmbedImage].self, forKey: .images)) ?? media?.images ?? []
        self.external = (try? container.decodeIfPresent(EmbedExternal.self, forKey: .external)) ?? media?.external
        self.video = container.contains(.playlist) ? (try? EmbedVideo(from: decoder)) : media?.video
        // `record` is the quoted `viewRecord` directly in `record#view`, but in
        // `recordWithMedia#view` it is the whole `record#view` object — one more
        // `record` level down. Probe both shapes.
        self.record = (try? container.decodeIfPresent(EmbedRecord.self, forKey: .record))
            ?? (try? container.decodeIfPresent(RecordViewWrapper.self, forKey: .record))?.record
    }
}

/// The `app.bsky.embed.record#view` object as nested inside
/// `recordWithMedia#view`: one extra `record` level around the `viewRecord`.
private struct RecordViewWrapper: Decodable {
    let record: EmbedRecord?

    enum CodingKeys: String, CodingKey { case record }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.record = try? container.decodeIfPresent(EmbedRecord.self, forKey: .record)
    }
}

/// A quoted post (`app.bsky.embed.record#view`'s `viewRecord`) hydrated enough
/// to render a quote card: the quoted post's identity, author, record value,
/// and its own media embeds. Non-post records and the viewNotFound /
/// viewBlocked / viewDetached variants fail this decode, which the tolerant
/// parent (`PostEmbed`) turns into a nil `record` — the quote card is simply
/// not rendered.
public struct EmbedRecord: Decodable, Equatable, Sendable {
    public let uri: String
    public let cid: String
    public let author: ProfileViewBasic
    public let value: PostRecord
    /// The quoted post's own embeds (images / external / video), used for the
    /// quote card's thumbnails. A quote nested inside a quote is not rendered.
    public let embeds: [PostEmbed]

    public init(uri: String, cid: String, author: ProfileViewBasic, value: PostRecord, embeds: [PostEmbed] = []) {
        self.uri = uri
        self.cid = cid
        self.author = author
        self.value = value
        self.embeds = embeds
    }

    enum CodingKeys: String, CodingKey { case uri, cid, author, value, embeds }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.uri = try container.decode(String.self, forKey: .uri)
        self.cid = try container.decode(String.self, forKey: .cid)
        self.author = try container.decode(ProfileViewBasic.self, forKey: .author)
        self.value = try container.decode(PostRecord.self, forKey: .value)
        self.embeds = (try? container.decode([PostEmbed].self, forKey: .embeds)) ?? []
    }
}

/// The hydrated video embed (`app.bsky.embed.video#view`): the HLS playlist URL
/// plus the optional poster thumbnail, alt text, and source aspect ratio. The
/// app renders the poster only; playback opens the post externally.
public struct EmbedVideo: Decodable, Equatable, Sendable {
    public let playlist: String
    public let thumbnail: String?
    public let alt: String?
    public let aspectRatio: ImageAspectRatio?

    public init(playlist: String, thumbnail: String? = nil, alt: String? = nil, aspectRatio: ImageAspectRatio? = nil) {
        self.playlist = playlist
        self.thumbnail = thumbnail
        self.alt = alt
        self.aspectRatio = aspectRatio
    }
}

/// The hydrated external-link card (`app.bsky.embed.external#view`'s
/// `viewExternal`): the link target plus the OGP-derived title, description, and
/// optional CDN thumbnail URL captured by the posting client.
public struct EmbedExternal: Decodable, Equatable, Sendable {
    public let uri: String
    public let title: String
    public let description: String
    public let thumb: String?

    public init(uri: String, title: String, description: String, thumb: String? = nil) {
        self.uri = uri
        self.title = title
        self.description = description
        self.thumb = thumb
    }
}

/// The pixel dimensions of an embedded image (`app.bsky.embed.defs#aspectRatio`),
/// used to lay the image out at its true proportions before it has loaded.
public struct ImageAspectRatio: Decodable, Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// One image in an `app.bsky.embed.images#view`: a thumbnail and full-size URL
/// plus its alt text and (optionally) its source aspect ratio.
public struct EmbedImage: Decodable, Equatable, Sendable {
    public let thumb: String
    public let fullsize: String
    public let alt: String
    public let aspectRatio: ImageAspectRatio?

    public init(thumb: String, fullsize: String, alt: String, aspectRatio: ImageAspectRatio? = nil) {
        self.thumb = thumb
        self.fullsize = fullsize
        self.alt = alt
        self.aspectRatio = aspectRatio
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
public enum FacetFeature: Codable, Equatable, Sendable {
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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .link(let uri):
            try container.encode("app.bsky.richtext.facet#link", forKey: .type)
            try container.encode(uri, forKey: .uri)
        case .mention(let did):
            try container.encode("app.bsky.richtext.facet#mention", forKey: .type)
            try container.encode(did, forKey: .did)
        case .tag(let tag):
            try container.encode("app.bsky.richtext.facet#tag", forKey: .type)
            try container.encode(tag, forKey: .tag)
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
