import Foundation
import BlueskyCore

/// One image attached to a draft: raw bytes plus its MIME type and alt text.
public struct ComposeImage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var data: Data
    public var mimeType: String
    public var alt: String

    public init(id: UUID = UUID(), data: Data, mimeType: String, alt: String = "") {
        self.id = id
        self.data = data
        self.mimeType = mimeType
        self.alt = alt
    }
}

/// The values needed to create a post: body text, up to four images, an optional
/// parent URI when the post is a reply, and an optional `quote` strong reference
/// when the post quotes another post.
public struct PostDraft: Equatable, Sendable {
    public var text: String
    public var images: [ComposeImage]
    public var replyParentURI: String?
    public var quote: StrongRef?

    public init(
        text: String, images: [ComposeImage] = [], replyParentURI: String? = nil, quote: StrongRef? = nil
    ) {
        self.text = text
        self.images = images
        self.replyParentURI = replyParentURI
        self.quote = quote
    }
}

/// The created post's identifiers, returned on success.
public struct PostResult: Equatable, Sendable {
    public let uri: String
    public let cid: String

    public init(uri: String, cid: String) {
        self.uri = uri
        self.cid = cid
    }
}
