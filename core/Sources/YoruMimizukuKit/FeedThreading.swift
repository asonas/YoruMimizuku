import Foundation

/// One feed row after thread grouping, with the visual-connector flags the row
/// needs to draw the Bluesky-web-style thread line between grouped posts.
public struct ThreadedFeedItem: Equatable, Sendable, Identifiable {
    public let post: PostDisplay
    /// A grouped predecessor (its parent in the same group) sits directly above.
    public let connectsToPrevious: Bool
    /// A grouped successor (a reply in the same group) sits directly below.
    public let connectsToNext: Bool

    public var id: String { post.id }

    public init(post: PostDisplay, connectsToPrevious: Bool = false, connectsToNext: Bool = false) {
        self.post = post
        self.connectsToPrevious = connectsToPrevious
        self.connectsToNext = connectsToNext
    }
}

/// Rearranges a newest-first feed page the way Bluesky's web client shows
/// threads: posts that belong to the same reply chain (typically an author's
/// self-thread, "1/3 … 3/3") are emitted as one block, oldest first, at the
/// feed position of the block's newest member. Posts whose parents are not on
/// the page are left where they are.
public enum FeedThreading {
    public static func arrange(_ posts: [PostDisplay]) -> [ThreadedFeedItem] {
        let byID = Dictionary(posts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Resolve each post to the topmost ancestor on this page that is still part
        // of the same author's self-thread: climb replyParent links only while the
        // parent shares the current post's author. The climb stops where the author
        // changes, so multi-author / branching replies do not collapse into one
        // chronological block. A visited set guards against (malformed) parent cycles.
        func groupKey(for post: PostDisplay) -> String {
            var current = post
            var visited: Set<String> = [post.id]
            while let parentID = current.replyParent?.post.id,
                  let parent = byID[parentID],
                  !visited.contains(parentID),
                  parent.authorHandle == current.authorHandle {
                visited.insert(parentID)
                current = parent
            }
            return current.id
        }

        var members: [String: [PostDisplay]] = [:]
        var emittedPostIDs = Set<String>()
        for post in posts where emittedPostIDs.insert(post.id).inserted {
            members[groupKey(for: post), default: []].append(post)
        }

        var items: [ThreadedFeedItem] = []
        var emittedGroups = Set<String>()
        for post in posts {
            let key = groupKey(for: post)
            guard emittedGroups.insert(key).inserted, let group = members[key] else { continue }
            let ordered = group.sorted {
                ($0.createdAt, $0.id) < ($1.createdAt, $1.id)
            }
            for (index, member) in ordered.enumerated() {
                items.append(ThreadedFeedItem(
                    post: member,
                    connectsToPrevious: index > 0,
                    connectsToNext: index < ordered.count - 1
                ))
            }
        }
        return items
    }
}

private func < (lhs: (Date, String), rhs: (Date, String)) -> Bool {
    lhs.0 != rhs.0 ? lhs.0 < rhs.0 : lhs.1 < rhs.1
}
