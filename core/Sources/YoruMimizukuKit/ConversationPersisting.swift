import Foundation

/// A persisted conversation tab: the anchored post's URI plus the display fields
/// the sidebar shows, so a restored tab renders correctly before its thread loads.
public struct SavedConversation: Codable, Equatable, Sendable {
    public let anchorID: String
    public let title: String
    public let handle: String
    public let subtitle: String

    public init(anchorID: String, title: String, handle: String, subtitle: String) {
        self.anchorID = anchorID
        self.title = title
        self.handle = handle
        self.subtitle = subtitle
    }
}

/// The persisted workspace state: the open conversation tabs and which one (by
/// anchor URI) was selected. Pinned tabs (home / notifications) are implicit.
public struct ConversationState: Codable, Equatable, Sendable {
    public var conversations: [SavedConversation]
    public var selectedAnchorID: String?

    public init(conversations: [SavedConversation] = [], selectedAnchorID: String? = nil) {
        self.conversations = conversations
        self.selectedAnchorID = selectedAnchorID
    }
}

/// Persists the open conversation tabs so they survive an app restart. The app
/// wires a `UserDefaults`-backed implementation; tests inject a fake.
public protocol ConversationPersisting: Sendable {
    func load() -> ConversationState
    func save(_ state: ConversationState)
}

/// A no-op store that keeps nothing across launches. The default for previews and
/// tests that do not exercise persistence.
public struct EphemeralConversationStore: ConversationPersisting {
    public init() {}
    public func load() -> ConversationState { ConversationState() }
    public func save(_ state: ConversationState) {}
}
