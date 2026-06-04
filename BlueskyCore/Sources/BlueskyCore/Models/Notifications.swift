import Foundation

/// Response of `app.bsky.notification.listNotifications`: a page of notifications
/// plus an optional pagination cursor. Unknown keys are ignored by `Decodable`.
public struct ListNotificationsResponse: Decodable, Equatable, Sendable {
    public let notifications: [BskyNotification]
    public let cursor: String?

    public init(notifications: [BskyNotification], cursor: String?) {
        self.notifications = notifications
        self.cursor = cursor
    }
}

/// Why a notification was generated. Modeled as a closed set with an `other`
/// escape hatch so an unrecognized reason (e.g. a future "starterpack-joined")
/// never breaks decoding of the whole page.
public enum NotificationReason: Equatable, Sendable {
    case like
    case repost
    case follow
    case mention
    case reply
    case quote
    case other(String)

    init(raw: String) {
        switch raw {
        case "like": self = .like
        case "repost": self = .repost
        case "follow": self = .follow
        case "mention": self = .mention
        case "reply": self = .reply
        case "quote": self = .quote
        default: self = .other(raw)
        }
    }
}

/// One notification (`app.bsky.notification.listNotifications#notification`). Only
/// the fields YoruMimizuku renders are modeled. `reasonSubject` is the post the
/// reaction targets (absent for follows); `record` carries text for reply/mention/
/// quote and is otherwise text-less.
public struct BskyNotification: Decodable, Equatable, Sendable {
    public let uri: String
    public let cid: String
    public let author: ProfileViewBasic
    public let reason: NotificationReason
    public let reasonSubject: String?
    public let record: NotificationRecord
    public let isRead: Bool
    public let indexedAt: String

    public init(
        uri: String,
        cid: String,
        author: ProfileViewBasic,
        reason: NotificationReason,
        reasonSubject: String?,
        record: NotificationRecord,
        isRead: Bool,
        indexedAt: String
    ) {
        self.uri = uri
        self.cid = cid
        self.author = author
        self.reason = reason
        self.reasonSubject = reasonSubject
        self.record = record
        self.isRead = isRead
        self.indexedAt = indexedAt
    }

    enum CodingKeys: String, CodingKey {
        case uri, cid, author, reason, reasonSubject, record, isRead, indexedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.uri = try container.decode(String.self, forKey: .uri)
        self.cid = try container.decode(String.self, forKey: .cid)
        self.author = try container.decode(ProfileViewBasic.self, forKey: .author)
        self.reason = NotificationReason(raw: try container.decode(String.self, forKey: .reason))
        self.reasonSubject = try container.decodeIfPresent(String.self, forKey: .reasonSubject)
        self.record = try container.decode(NotificationRecord.self, forKey: .record)
        self.isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        self.indexedAt = try container.decode(String.self, forKey: .indexedAt)
    }
}

/// The notification's underlying record. Its concrete shape varies by reason
/// (a like, a follow, a post). We only read the optional `text` (present on
/// reply/mention/quote posts) and tolerate every other shape.
public struct NotificationRecord: Decodable, Equatable, Sendable {
    public let text: String?

    public init(text: String?) {
        self.text = text
    }

    enum CodingKeys: String, CodingKey { case text }

    public init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        self.text = try? container?.decodeIfPresent(String.self, forKey: .text)
    }
}
