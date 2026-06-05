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

extension FilterTerm {
    /// The `searchPosts` query fragment for this term, or nil when the value is
    /// blank after trimming AND stripping a leading `@`/`#` (so a value of just
    /// "@" or "#" yields no fragment rather than a degenerate `from:`/`#`).
    public var fragment: String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .keyword:
            return v.isEmpty ? nil : v
        case .user:
            let handle = Self.stripLeading("@", v)
            return handle.isEmpty ? nil : "from:" + handle
        case .hashtag:
            let tag = Self.stripLeading("#", v)
            return tag.isEmpty ? nil : "#" + tag
        case .mention:
            let handle = Self.stripLeading("@", v)
            return handle.isEmpty ? nil : "mentions:" + handle
        }
    }

    private static func stripLeading(_ ch: Character, _ s: String) -> String {
        s.hasPrefix(String(ch)) ? String(s.dropFirst()) : s
    }
}

extension SavedFilter {
    /// The `searchPosts` queries this filter expands to. `and` joins every
    /// non-blank fragment into a single query; `or` yields one query per fragment
    /// (merged client-side by the loader). Empty when there are no usable terms.
    public var subqueries: [String] {
        let fragments = terms.compactMap(\.fragment)
        guard !fragments.isEmpty else { return [] }
        switch combinator {
        case .and: return [fragments.joined(separator: " ")]
        case .or: return fragments
        }
    }

    /// Label used when the user leaves the name blank: the expanded subqueries
    /// joined with a combinator-appropriate separator.
    public var fallbackName: String {
        subqueries.joined(separator: combinator == .or ? " | " : " ")
    }

    /// One-line summary for the sidebar meta row.
    public var summary: String {
        switch combinator {
        case .and: return subqueries.first ?? ""
        case .or: return "OR: " + subqueries.joined(separator: ", ")
        }
    }
}
