import Foundation

/// The kind of a single filter condition, which determines how its value is
/// rendered into a `searchPosts` query fragment.
public enum FilterTermKind: String, Codable, Sendable, CaseIterable {
    case keyword   // value verbatim
    case user      // from:<handle>
    case hashtag   // #<tag>
    case mention   // mentions:<handle>
}

/// One condition row in a structured filter.
public struct FilterTerm: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var kind: FilterTermKind
    public var value: String

    public init(id: UUID = UUID(), kind: FilterTermKind, value: String) {
        self.id = id
        self.kind = kind
        self.value = value
    }
}

/// How a filter's condition rows are combined. `and` joins them into one query;
/// `or` runs each as its own search and merges the results client-side (the
/// Bluesky search API has no boolean OR).
public enum FilterCombinator: String, Codable, Sendable {
    case and
    case or
}

/// A saved search subscribed as a sidebar tab: a list of typed condition rows
/// combined by `combinator`. A pure value type so it can later be synced verbatim
/// (e.g. via iCloud). Decoding migrates the legacy single-`query` shape to one
/// keyword term so older persisted filters keep working.
public struct SavedFilter: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var terms: [FilterTerm]
    public var combinator: FilterCombinator
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        terms: [FilterTerm],
        combinator: FilterCombinator = .and,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.terms = terms
        self.combinator = combinator
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, terms, combinator, createdAt, query
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? Date(timeIntervalSince1970: 0)
        if let terms = try c.decodeIfPresent([FilterTerm].self, forKey: .terms) {
            self.terms = terms
            self.combinator = try c.decodeIfPresent(FilterCombinator.self, forKey: .combinator) ?? .and
        } else {
            // Legacy migration: a single raw `query` becomes one keyword term.
            let query = try c.decodeIfPresent(String.self, forKey: .query) ?? ""
            self.terms = [FilterTerm(kind: .keyword, value: query)]
            self.combinator = .and
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(terms, forKey: .terms)
        try c.encode(combinator, forKey: .combinator)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
