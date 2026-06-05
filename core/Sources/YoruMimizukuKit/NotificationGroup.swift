import Foundation
import BlueskyCore

/// A notifications-tab row after aggregation. Likes and reposts that target the
/// same post are collapsed into a single group (so "5 people liked your post" is
/// one row instead of five); every other reason stays one notification per group.
/// The target post snippet (`subjectText` / `subjectImageURL`) is filled in after
/// the post is fetched via `app.bsky.feed.getPosts`.
public struct NotificationGroup: Identifiable, Equatable, Sendable {
    /// One person involved in the group (e.g. one of the people who liked a post).
    public struct Actor: Equatable, Sendable {
        public let displayName: String
        public let handle: String
        public let avatarURL: URL?

        public init(displayName: String, handle: String, avatarURL: URL?) {
            self.displayName = displayName
            self.handle = handle
            self.avatarURL = avatarURL
        }
    }

    public let id: String
    public let reason: NotificationReason
    public let actors: [Actor]
    public let subjectURI: String?
    public let subjectText: String?
    public let subjectImageURL: URL?
    /// The reply/mention/quote body, carried straight from the single notification.
    public let text: String?
    public let latestCreatedAt: Date
    public let isRead: Bool

    public init(
        id: String,
        reason: NotificationReason,
        actors: [Actor],
        subjectURI: String?,
        subjectText: String? = nil,
        subjectImageURL: URL? = nil,
        text: String? = nil,
        latestCreatedAt: Date,
        isRead: Bool
    ) {
        self.id = id
        self.reason = reason
        self.actors = actors
        self.subjectURI = subjectURI
        self.subjectText = subjectText
        self.subjectImageURL = subjectImageURL
        self.text = text
        self.latestCreatedAt = latestCreatedAt
        self.isRead = isRead
    }

    /// The Bluesky-style summary line, e.g. "aliceおよび他2人があなたの投稿をいいねしました".
    /// The lead actor's display name leads, the remaining count folds into "および他N人",
    /// and the verb phrase names what they did to "あなたの投稿" (your post). The relative
    /// time is rendered separately by the view as a trailing " · 1分".
    public var actionSummary: String {
        let lead = actors.first.map { $0.displayName.isEmpty ? $0.handle : $0.displayName } ?? ""
        let others = max(0, actors.count - 1)
        let subject = others > 0 ? "\(lead)および他\(others)人" : lead
        return subject + Self.verbPhrase(for: reason)
    }

    private static func verbPhrase(for reason: NotificationReason) -> String {
        switch reason {
        case .like: return "があなたの投稿をいいねしました"
        case .repost: return "があなたの投稿をリポストしました"
        case .follow: return "があなたをフォローしました"
        case .mention: return "があなたにメンションしました"
        case .reply: return "があなたの投稿に返信しました"
        case .quote: return "があなたの投稿を引用しました"
        case .other: return "のアクティビティがありました"
        }
    }

    /// Return a copy with the resolved target-post snippet attached.
    public func withSubject(text: String?, imageURL: URL?) -> NotificationGroup {
        NotificationGroup(
            id: id, reason: reason, actors: actors, subjectURI: subjectURI,
            subjectText: text, subjectImageURL: imageURL, text: self.text,
            latestCreatedAt: latestCreatedAt, isRead: isRead
        )
    }

    /// Whether this reason collapses multiple notifications on the same subject
    /// into one row. Only likes and reposts aggregate; replies/mentions/quotes
    /// carry distinct bodies and follows have no subject.
    private static func aggregates(_ reason: NotificationReason) -> Bool {
        switch reason {
        case .like, .repost: return true
        default: return false
        }
    }

    private static func key(_ reason: NotificationReason) -> String {
        switch reason {
        case .like: return "like"
        case .repost: return "repost"
        case .follow: return "follow"
        case .mention: return "mention"
        case .reply: return "reply"
        case .quote: return "quote"
        case let .other(raw): return "other:\(raw)"
        }
    }

    /// Collapse a notifications page into display groups, preserving the order of
    /// each group's first appearance (which keeps the API's newest-first order).
    public static func group(_ items: [NotificationDisplay]) -> [NotificationGroup] {
        var order: [String] = []
        var buckets: [String: [NotificationDisplay]] = [:]

        for item in items {
            let groupKey: String
            if aggregates(item.reason), let subject = item.subjectURI {
                groupKey = "\(key(item.reason))|\(subject)"
            } else {
                groupKey = "single|\(item.id)"
            }
            if buckets[groupKey] == nil {
                order.append(groupKey)
                buckets[groupKey] = []
            }
            buckets[groupKey]?.append(item)
        }

        return order.compactMap { groupKey in
            guard let members = buckets[groupKey], let first = members.first else { return nil }
            let actors = members.map {
                Actor(displayName: $0.authorDisplayName, handle: $0.authorHandle, avatarURL: $0.avatarURL)
            }
            return NotificationGroup(
                id: groupKey,
                reason: first.reason,
                actors: actors,
                subjectURI: first.subjectURI,
                text: first.text,
                latestCreatedAt: members.map(\.createdAt).max() ?? first.createdAt,
                isRead: members.allSatisfy(\.isRead)
            )
        }
    }
}
