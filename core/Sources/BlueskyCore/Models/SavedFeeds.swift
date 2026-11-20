import Foundation

/// `app.bsky.actor.getPreferences`, reduced to the saved feeds the account keeps
/// in `app.bsky.actor.defs#savedFeedsPrefV2`. Other preference kinds are skipped.
public struct PreferencesResponse: Decodable, Equatable, Sendable {
    /// The saved items in the order the account keeps them (empty when the
    /// account has never saved any).
    public let savedFeeds: [SavedFeedItem]

    public init(savedFeeds: [SavedFeedItem]) {
        self.savedFeeds = savedFeeds
    }

    private enum CodingKeys: String, CodingKey { case preferences }

    /// One element of `preferences`: only `$type` and, for saved feeds, `items`
    /// are read, so unknown preference shapes never fail the decode.
    private struct Preference: Decodable {
        let type: String
        let items: [SavedFeedItem]?
        private enum CodingKeys: String, CodingKey {
            case type = "$type"
            case items
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preferences = try container.decode([Preference].self, forKey: .preferences)
        savedFeeds = preferences.first { $0.type == "app.bsky.actor.defs#savedFeedsPrefV2" }?.items ?? []
    }
}

/// `app.bsky.actor.defs#savedFeed`. `type` is `timeline`, `feed`, or `list`
/// today; it stays a string so a new kind is skipped rather than failing.
public struct SavedFeedItem: Decodable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let value: String
    public let pinned: Bool

    public init(id: String, type: String, value: String, pinned: Bool) {
        self.id = id
        self.type = type
        self.value = value
        self.pinned = pinned
    }
}

/// `app.bsky.feed.getFeedGenerators`.
public struct FeedGeneratorsResponse: Decodable, Equatable, Sendable {
    public let feeds: [FeedGeneratorView]
}

/// `app.bsky.feed.defs#generatorView`, the fields the sidebar shows.
public struct FeedGeneratorView: Decodable, Equatable, Sendable {
    public let uri: String
    public let creator: ProfileViewBasic
    public let displayName: String
    public let description: String?
    public let avatar: String?
}

/// `app.bsky.graph.getList`, read only for the list itself.
public struct ListResponse: Decodable, Equatable, Sendable {
    public let list: ListView
}

/// `app.bsky.graph.defs#listView`, the fields the sidebar shows.
public struct ListView: Decodable, Equatable, Sendable {
    public let uri: String
    public let name: String
    public let description: String?
    public let avatar: String?
    public let creator: ProfileViewBasic
}
