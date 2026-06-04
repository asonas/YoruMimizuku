import Foundation
import BlueskyCore

/// A notification as shown in the notifications tab. UI-framework-agnostic so it
/// can be unit tested and reused across platforms. The `reason` drives the row's
/// icon and verb ("liked", "followed you", "replied"); `text` is the reply/mention
/// post body when present.
public struct NotificationDisplay: Identifiable, Equatable, Sendable {
    public let id: String
    public let reason: NotificationReason
    public let authorDisplayName: String
    public let authorHandle: String
    public let avatarURL: URL?
    public let text: String?
    public let createdAt: Date
    public let isRead: Bool

    public init(
        id: String,
        reason: NotificationReason,
        authorDisplayName: String,
        authorHandle: String,
        avatarURL: URL? = nil,
        text: String? = nil,
        createdAt: Date,
        isRead: Bool = false
    ) {
        self.id = id
        self.reason = reason
        self.authorDisplayName = authorDisplayName
        self.authorHandle = authorHandle
        self.avatarURL = avatarURL
        self.text = text
        self.createdAt = createdAt
        self.isRead = isRead
    }
}

extension NotificationDisplay {
    /// Map a `BlueskyCore` notification into the UI-facing display value. The id
    /// combines uri and cid so the same actor liking and replying yields distinct
    /// rows; `indexedAt` becomes the timestamp.
    public init(_ notification: BskyNotification) {
        let author = notification.author
        self.init(
            id: "\(notification.uri)|\(notification.cid)",
            reason: notification.reason,
            authorDisplayName: author.displayName ?? author.handle,
            authorHandle: author.handle,
            avatarURL: author.avatar.flatMap(URL.init(string:)),
            text: notification.record.text,
            createdAt: PostDisplay.parseISO8601(notification.indexedAt) ?? Date(timeIntervalSince1970: 0),
            isRead: notification.isRead
        )
    }
}
