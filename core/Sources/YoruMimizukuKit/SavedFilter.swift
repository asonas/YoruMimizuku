import Foundation

/// A saved search subscribed as a sidebar tab. `query` is the raw
/// `app.bsky.feed.searchPosts` query (e.g. `#swift from:alice.bsky.social`);
/// `name` is the user-facing tab label. A pure value type so it can later be
/// synced verbatim (e.g. via iCloud) without UI/OS coupling.
public struct SavedFilter: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var query: String
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, query: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.query = query
        self.createdAt = createdAt
    }
}
