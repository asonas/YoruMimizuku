import Foundation

/// An opaque pagination cursor for an OR filter, holding one sub-cursor per
/// subquery (aligned by position). A nil entry means that subquery is exhausted
/// or not yet fetched. Serialized to a single string to fit the `TimelineLoading`
/// single-cursor interface.
public struct CompositeCursor: Codable, Equatable, Sendable {
    public var cursors: [String?]

    public init(cursors: [String?]) {
        self.cursors = cursors
    }

    /// Marks our own encoding, so a server's cursor is never read as one.
    private static let prefix = "yoru-or:"

    /// Encode to one opaque cursor string, or nil when every sub-cursor is
    /// nil (nothing more to load anywhere).
    public func encoded() -> String? {
        guard cursors.contains(where: { $0 != nil }) else { return nil }
        guard let data = try? JSONEncoder().encode(self), let json = String(data: data, encoding: .utf8) else { return nil }
        return Self.prefix + json
    }

    /// Decode from an opaque cursor string; a nil string (first page) or one we
    /// did not encode yields nil.
    public static func decode(_ string: String?) -> CompositeCursor? {
        guard let string, string.hasPrefix(prefix),
              let data = string.dropFirst(prefix.count).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CompositeCursor.self, from: data)
    }

    /// The cursor to send for a single-term filter: the server's cursor as is,
    /// or nil (start over) for a composite cursor left from when the filter had
    /// several terms.
    public static func singleQueryCursor(_ cursor: String?) -> String? {
        decode(cursor) == nil ? cursor : nil
    }

    /// What one subquery does for a page.
    public enum Fetch: Equatable, Sendable {
        case fetch(cursor: String?)
        /// An earlier page reached its end; nothing more to load.
        case exhausted
    }

    /// The fetch for each of `subqueryCount` subqueries, in order, given the
    /// page's cursor. No cursor, or one that does not match the subqueries (the
    /// filter was edited since), starts every subquery from the beginning.
    public static func pageFetches(cursor: String?, subqueryCount: Int) -> [Fetch] {
        guard let decoded = decode(cursor), decoded.cursors.count == subqueryCount else {
            return Array(repeating: .fetch(cursor: nil), count: subqueryCount)
        }
        return decoded.cursors.map { $0.map { .fetch(cursor: $0) } ?? .exhausted }
    }
}

/// Pure merge logic for OR filters.
public enum FilterSearchMerge {
    /// Merge per-subquery result pages into a single feed: keep the first
    /// occurrence of each post id, then sort newest-first by `createdAt`.
    public static func merge(_ pages: [[PostDisplay]]) -> [PostDisplay] {
        var seen = Set<String>()
        var all: [PostDisplay] = []
        for page in pages {
            for post in page where seen.insert(post.id).inserted {
                all.append(post)
            }
        }
        return all.sorted { $0.createdAt > $1.createdAt }
    }
}
