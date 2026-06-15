import Foundation

/// High-level account management over an `AccountStore`: add a freshly logged-in
/// account (becomes current), list, switch, remove, and read the current account.
/// Token refresh and its scheduling are out of scope for this layer.
public struct AccountManager: Sendable {
    private let store: AccountStore
    /// Shared across every service so concurrent pollers coalesce their token
    /// refreshes instead of racing to consume the same single-use refresh token.
    public let refreshGate: RefreshGate

    public init(store: AccountStore, refreshGate: RefreshGate = RefreshGate()) {
        self.store = store
        self.refreshGate = refreshGate
    }

    /// Persist a login result (with its DPoP key) and make it the current account.
    @discardableResult
    public func add(
        loginResult: OAuthLoginResult,
        handle: String?,
        dpopPrivateKeyRaw: Data
    ) throws -> PersistedAccount {
        let account = PersistedAccount(
            loginResult: loginResult, handle: handle, dpopPrivateKeyRaw: dpopPrivateKeyRaw
        )
        try store.save(account)
        try store.setCurrent(did: account.did)
        return account
    }

    /// Replace the stored tokens for an account (e.g. after a `refresh_token`
    /// renewal), preserving everything else. Throws `unknownAccount` if the DID
    /// is not stored.
    @discardableResult
    public func updateTokens(
        did: String,
        accessToken: String,
        refreshToken: String?,
        scope: String?
    ) throws -> PersistedAccount {
        guard var account = try store.account(did: did) else {
            throw AccountError.unknownAccount(did)
        }
        account.accessToken = accessToken
        account.refreshToken = refreshToken
        account.scope = scope
        try store.save(account)
        return account
    }

    /// The current account, or nil if none is selected.
    public func current() throws -> PersistedAccount? {
        guard let did = try store.index().currentDID else { return nil }
        return try store.account(did: did)
    }

    /// All known account DIDs, in insertion order.
    public func allDIDs() throws -> [String] {
        try store.index().dids
    }

    /// Lightweight account list for an account-switcher UI: each known account's
    /// DID and handle, in insertion order, without exposing tokens or the DPoP key.
    public func summaries() throws -> [AccountSummary] {
        try allDIDs().compactMap { did in
            try store.account(did: did).map { AccountSummary(did: $0.did, handle: $0.handle) }
        }
    }

    /// Switch the current account. Throws `unknownAccount` if the DID is unknown.
    public func switchTo(did: String) throws {
        try store.setCurrent(did: did)
    }

    /// Remove an account; clears current if it pointed at the removed account.
    public func remove(did: String) throws {
        try store.remove(did: did)
    }

    /// Remove `did`, then make the first remaining account current and return its
    /// DID, or nil when none remain. Centralizes the "log out / drop a dead session
    /// and fall through to the next account" flow so the UI and the session-expiry
    /// handler share one implementation.
    @discardableResult
    public func removeAndAdvance(did: String) throws -> String? {
        try remove(did: did)
        guard let next = try allDIDs().first else { return nil }
        try switchTo(did: next)
        return next
    }
}

/// A single account reduced to what an account-switcher menu needs: the DID and
/// the handle. Carries no tokens or key material.
public struct AccountSummary: Equatable, Sendable {
    public let did: String
    public let handle: String?

    public init(did: String, handle: String?) {
        self.did = did
        self.handle = handle
    }
}
