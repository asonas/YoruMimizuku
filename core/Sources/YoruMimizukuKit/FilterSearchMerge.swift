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

    /// JSON-encode to one opaque cursor string, or nil when every sub-cursor is
    /// nil (nothing more to load anywhere).
    public func encoded() -> String? {
        guard cursors.contains(where: { $0 != nil }) else { return nil }
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode from an opaque cursor string; a nil string (first page) yields nil.
    public static func decode(_ string: String?) -> CompositeCursor? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CompositeCursor.self, from: data)
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
