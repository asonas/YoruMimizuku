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

    /// One element of `preferences`. `items` is read only for saved feeds:
    /// other kinds (muted words, hidden posts) use `items` with other shapes.
    private struct Preference: Decodable {
        let items: [SavedFeedItem]?
        private enum CodingKeys: String, CodingKey {
            case type = "$type"
            case items
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decodeIfPresent(String.self, forKey: .type)
            items = type == "app.bsky.actor.defs#savedFeedsPrefV2"
                ? try container.decode([SavedFeedItem].self, forKey: .items)
                : nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preferences = try container.decode([Preference].self, forKey: .preferences)
        savedFeeds = preferences.lazy.compactMap(\.items).first ?? []
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

    public init(uri: String, creator: ProfileViewBasic, displayName: String, description: String?, avatar: String?) {
        self.uri = uri
        self.creator = creator
        self.displayName = displayName
        self.description = description
        self.avatar = avatar
    }
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
    /// `app.bsky.graph.defs#curatelist`, `#modlist` or `#referencelist`.
    public let purpose: String?

    public init(
        uri: String, name: String, description: String?, avatar: String?, creator: ProfileViewBasic,
        purpose: String? = nil
    ) {
        self.uri = uri
        self.name = name
        self.description = description
        self.avatar = avatar
        self.creator = creator
        self.purpose = purpose
    }
}

/// `app.bsky.graph.getListsWithMembership`: the session user's own lists, each
/// with the list item that puts the asked-about actor on it (nil when absent).
public struct ListsWithMembershipResponse: Decodable, Equatable, Sendable {
    public let listsWithMembership: [ListWithMembership]
    public let cursor: String?
}

public struct ListWithMembership: Decodable, Equatable, Sendable {
    public let list: ListView
    public let listItem: ListItemRef?

    public init(list: ListView, listItem: ListItemRef?) {
        self.list = list
        self.listItem = listItem
    }
}

/// `app.bsky.graph.defs#listItemView`, read only for the record's AT-URI (its
/// rkey is what removing the actor from the list deletes).
public struct ListItemRef: Decodable, Equatable, Sendable {
    public let uri: String

    public init(uri: String) { self.uri = uri }
}
