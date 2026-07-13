/// A request to re-authenticate an existing account whose OAuth session expired.
/// `handle` pre-fills the login field (empty when the stored account has no handle).
public struct ReauthRequest: Equatable, Sendable {
    public let did: String
    public let handle: String

    public init(did: String, handle: String) {
        self.did = did
        self.handle = handle
    }
}

/// Pure decision for turning a session-expiry event into a re-auth intent. Kept
/// UI-free and out of the views so the idempotency rule is unit-testable.
public enum SessionReauth {
    /// The re-auth request to present, or nil for a no-op. Returns nil when a
    /// re-auth is already pending (so repeated poll-driven `invalid_grant`
    /// notifications never re-present the sheet) or when there is no current
    /// account. A nil handle pre-fills as empty text.
    public static func onExpiry(currentDID: String?, currentHandle: String?, isPending: Bool) -> ReauthRequest? {
        guard !isPending, let did = currentDID else { return nil }
        return ReauthRequest(did: did, handle: currentHandle ?? "")
    }
}
