import Foundation

/// High-level account management over an `AccountStore`: add a freshly logged-in
/// account (becomes current), list, switch, remove, and read the current account.
/// Token refresh and its scheduling are out of scope for this layer.
public struct AccountManager: Sendable {
    private let store: AccountStore
    /// Shared across every service so concurrent pollers coalesce their token
    /// refreshes instead of racing to consume the same single-use refresh token.
    public let refreshGate: RefreshGate
    /// Serializes every write to stored accounts, so a token update's check and
    /// save cannot interleave with another update, a re-login or a removal.
    /// Recursive because `removeAndAdvance` calls `remove`.
    private let writes: NSRecursiveLock

    /// Without a `refreshGate`, the manager makes one that saves each renewal as
    /// it happens, so the issued tokens are stored even if the request that
    /// renewed fails afterwards.
    public init(store: AccountStore, refreshGate: RefreshGate? = nil) {
        let writes = NSRecursiveLock()
        self.store = store
        self.writes = writes
        self.refreshGate = refreshGate ?? RefreshGate(onRenewed: { used, issued in
            Self.saveRenewal(store: store, writes: writes, used: used, issued: issued)
        })
    }

    /// Store a renewal for the account whose refresh token is still `used`; an
    /// account already past it (or none) is left alone.
    private static func saveRenewal(store: AccountStore, writes: NSRecursiveLock, used: String, issued: TokenResponse) {
        writes.lock()
        defer { writes.unlock() }
        guard let dids = try? store.index().dids else { return }
        for did in dids {
            guard var account = try? store.account(did: did), account.refreshToken == used else { continue }
            account.accessToken = issued.accessToken
            if let refreshToken = issued.refreshToken { account.refreshToken = refreshToken }
            if let scope = issued.scope { account.scope = scope }
            try? store.save(account)
            return
        }
    }

    /// Persist a login result (with its DPoP key) and make it the current account.
    @discardableResult
    public func add(
        loginResult: OAuthLoginResult,
        handle: String?,
        dpopPrivateKeyRaw: Data
    ) throws -> PersistedAccount {
        writes.lock()
        defer { writes.unlock() }
        let account = PersistedAccount(
            loginResult: loginResult, handle: handle, dpopPrivateKeyRaw: dpopPrivateKeyRaw
        )
        try store.save(account)
        try store.setCurrent(did: account.did)
        return account
    }

    /// Save tokens a renewal issued for `did` and return the stored account.
    /// `session` is the DPoP key the renewing request signed with: tokens from a
    /// session replaced by a later sign-in are dropped. A refresh token the
    /// shared `refreshGate` has already used is dropped too, so a request that
    /// renewed earlier but reports late cannot bring back a token the server has
    /// invalidated. A nil `refreshToken` or `scope` keeps the stored one.
    /// Throws `unknownAccount` if the DID is not stored.
    @discardableResult
    public func updateTokens(
        did: String,
        session: Data,
        accessToken: String,
        refreshToken: String?,
        scope: String?
    ) throws -> PersistedAccount {
        writes.lock()
        defer { writes.unlock() }
        guard var account = try store.account(did: did) else {
            throw AccountError.unknownAccount(did)
        }
        guard account.dpopPrivateKeyRaw == session else { return account }
        if let refreshToken, refreshGate.hasUsed(refreshToken) { return account }
        account.accessToken = accessToken
        if let refreshToken { account.refreshToken = refreshToken }
        if let scope { account.scope = scope }
        try store.save(account)
        return account
    }

    /// The current account, or nil if none is selected.
    public func current() throws -> PersistedAccount? {
        guard let did = try store.index().currentDID else { return nil }
        return try store.account(did: did)
    }

    /// Return the credentials for the account being displayed in a specific window.
    public func account(did: String) throws -> PersistedAccount? {
        try store.account(did: did)
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
        writes.lock()
        defer { writes.unlock() }
        try store.setCurrent(did: did)
    }

    /// Remove an account; clears current if it pointed at the removed account.
    public func remove(did: String) throws {
        writes.lock()
        defer { writes.unlock() }
        try store.remove(did: did)
    }

    /// Remove `did`, then make the first remaining account current and return its
    /// DID, or nil when none remain. Centralizes the "log out / drop a dead session
    /// and fall through to the next account" flow so the UI and the session-expiry
    /// handler share one implementation.
    @discardableResult
    public func removeAndAdvance(did: String) throws -> String? {
        writes.lock()
        defer { writes.unlock() }
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
