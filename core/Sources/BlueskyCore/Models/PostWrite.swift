import Foundation

/// A blob reference (`blob`) returned by `com.atproto.repo.uploadBlob` and embedded
/// back into a record. JSON shape: `{ "$type":"blob", "ref":{"$link":<cid>},
/// "mimeType":..., "size":... }`.
public struct BlobRef: Codable, Equatable, Sendable {
    public let cid: String
    public let mimeType: String
    public let size: Int

    public init(cid: String, mimeType: String, size: Int) {
        self.cid = cid
        self.mimeType = mimeType
        self.size = size
    }

    enum CodingKeys: String, CodingKey { case type = "$type", ref, mimeType, size }
    enum RefKeys: String, CodingKey { case link = "$link" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ref = try c.nestedContainer(keyedBy: RefKeys.self, forKey: .ref)
        self.cid = try ref.decode(String.self, forKey: .link)
        self.mimeType = try c.decode(String.self, forKey: .mimeType)
        self.size = try c.decode(Int.self, forKey: .size)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("blob", forKey: .type)
        var ref = c.nestedContainer(keyedBy: RefKeys.self, forKey: .ref)
        try ref.encode(cid, forKey: .link)
        try c.encode(mimeType, forKey: .mimeType)
        try c.encode(size, forKey: .size)
    }
}

/// One rich-text facet for a record write. Encodes to `{ "index":{byteStart,byteEnd},
/// "features":[<feature>] }`.
public struct FacetWrite: Encodable, Equatable, Sendable {
    public let byteStart: Int
    public let byteEnd: Int
    public let feature: FacetFeature

    public init(byteStart: Int, byteEnd: Int, feature: FacetFeature) {
        self.byteStart = byteStart
        self.byteEnd = byteEnd
        self.feature = feature
    }

    enum CodingKeys: String, CodingKey { case index, features }
    enum IndexKeys: String, CodingKey { case byteStart, byteEnd }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var index = c.nestedContainer(keyedBy: IndexKeys.self, forKey: .index)
        try index.encode(byteStart, forKey: .byteStart)
        try index.encode(byteEnd, forKey: .byteEnd)
        try c.encode([feature], forKey: .features)
    }
}

/// One image in an `app.bsky.embed.images` write.
public struct ImageWrite: Encodable, Equatable, Sendable {
    public let image: BlobRef
    public let alt: String

    public init(image: BlobRef, alt: String) {
        self.image = image
        self.alt = alt
    }
}

/// The images embed for a record write (`app.bsky.embed.images`).
public struct ImagesEmbedWrite: Encodable, Equatable, Sendable {
    public let images: [ImageWrite]

    public init(images: [ImageWrite]) {
        self.images = images
    }

    enum CodingKeys: String, CodingKey { case type = "$type", images }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("app.bsky.embed.images", forKey: .type)
        try c.encode(images, forKey: .images)
    }
}

/// A strong reference (`com.atproto.repo.strongRef`): a record's uri + cid.
public struct StrongRef: Codable, Equatable, Sendable {
    public let uri: String
    public let cid: String

    public init(uri: String, cid: String) {
        self.uri = uri
        self.cid = cid
    }
}

/// The reply refs for a post record write: the conversation root and the immediate parent.
public struct ReplyRefWrite: Encodable, Equatable, Sendable {
    public let root: StrongRef
    public let parent: StrongRef

    public init(root: StrongRef, parent: StrongRef) {
        self.root = root
        self.parent = parent
    }
}

/// A post record for `createRecord` (`app.bsky.feed.post`). Encodes `$type`; omits
/// `facets`/`embed`/`reply` when absent so empty fields never reach the PDS.
public struct PostRecordWrite: Encodable, Equatable, Sendable {
    public let text: String
    public let createdAt: String
    public let facets: [FacetWrite]
    public let embed: ImagesEmbedWrite?
    public let reply: ReplyRefWrite?

    public init(text: String, createdAt: String, facets: [FacetWrite],
                embed: ImagesEmbedWrite?, reply: ReplyRefWrite?) {
        self.text = text
        self.createdAt = createdAt
        self.facets = facets
        self.embed = embed
        self.reply = reply
    }

    enum CodingKeys: String, CodingKey { case type = "$type", text, createdAt, facets, embed, reply }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("app.bsky.feed.post", forKey: .type)
        try c.encode(text, forKey: .text)
        try c.encode(createdAt, forKey: .createdAt)
        if !facets.isEmpty { try c.encode(facets, forKey: .facets) }
        try c.encodeIfPresent(embed, forKey: .embed)
        try c.encodeIfPresent(reply, forKey: .reply)
    }
}

/// A `app.bsky.feed.like` record write: a strong reference to the liked post plus
/// the like's `createdAt`. Encodes the `$type` discriminator.
public struct LikeRecordWrite: Encodable, Equatable, Sendable {
    public let subject: StrongRef
    public let createdAt: String

    public init(subject: StrongRef, createdAt: String) {
        self.subject = subject
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey { case type = "$type", subject, createdAt }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("app.bsky.feed.like", forKey: .type)
        try c.encode(subject, forKey: .subject)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

/// A `app.bsky.feed.repost` record write: a strong reference to the reposted post
/// plus the repost's `createdAt`. Encodes the `$type` discriminator.
public struct RepostRecordWrite: Encodable, Equatable, Sendable {
    public let subject: StrongRef
    public let createdAt: String

    public init(subject: StrongRef, createdAt: String) {
        self.subject = subject
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey { case type = "$type", subject, createdAt }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("app.bsky.feed.repost", forKey: .type)
        try c.encode(subject, forKey: .subject)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

/// `com.atproto.repo.deleteRecord` request body identifying the record to remove.
public struct DeleteRecordRequest: Encodable, Equatable, Sendable {
    public let repo: String
    public let collection: String
    public let rkey: String

    public init(repo: String, collection: String, rkey: String) {
        self.repo = repo
        self.collection = collection
        self.rkey = rkey
    }
}

/// `createRecord` request body wrapping a typed record.
public struct CreateRecordRequest<Record: Encodable>: Encodable {
    public let repo: String
    public let collection: String
    public let record: Record

    public init(repo: String, collection: String, record: Record) {
        self.repo = repo
        self.collection = collection
        self.record = record
    }
}

/// `com.atproto.repo.uploadBlob` response.
public struct UploadBlobResponse: Decodable, Equatable, Sendable {
    public let blob: BlobRef
}

/// `com.atproto.repo.createRecord` response.
public struct CreateRecordResponse: Decodable, Equatable, Sendable {
    public let uri: String
    public let cid: String
}

/// Minimal `app.bsky.actor.getProfile` decode used to resolve a mention handle to a DID.
public struct ResolveDIDResponse: Decodable, Equatable, Sendable {
    public let did: String
}

/// Minimal `com.atproto.repo.getRecord` decode used to build reply refs from a parent URI.
public struct GetRecordResponse: Decodable, Equatable, Sendable {
    public let uri: String
    public let cid: String
    public let replyRoot: StrongRef?

    enum CodingKeys: String, CodingKey { case uri, cid, value }
    enum ValueKeys: String, CodingKey { case reply }
    enum ReplyKeys: String, CodingKey { case root }

    public init(uri: String, cid: String, replyRoot: StrongRef?) {
        self.uri = uri
        self.cid = cid
        self.replyRoot = replyRoot
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.uri = try c.decode(String.self, forKey: .uri)
        self.cid = try c.decode(String.self, forKey: .cid)
        let value = try? c.nestedContainer(keyedBy: ValueKeys.self, forKey: .value)
        let reply = try? value?.nestedContainer(keyedBy: ReplyKeys.self, forKey: .reply)
        self.replyRoot = try? reply?.decode(StrongRef.self, forKey: .root)
    }
}
