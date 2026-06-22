import Foundation
import CryptoKit
import BlueskyCore

/// Shared plumbing for the live loaders. Restores the current account's DPoP key,
/// builds the DPoP-bound request sender and metadata resolver, and persists any
/// tokens a service refreshed mid-request. This keeps each loader down to the one
/// XRPC call it owns instead of repeating the same setup four times.
struct LiveServiceContext {
    let account: PersistedAccount
    let issuer: URL
    let sender: DPoPRequestSender
    let metadataResolver: OAuthMetadataResolver
    let config: OAuthClientConfig
    /// Shared refresh coalescer so concurrent loaders never race to consume the
    /// same single-use refresh token.
    let refreshGate: RefreshGate
    private let accountManager: AccountManager

    enum ContextError: Error { case noCurrentAccount, invalidIssuer }

    init(accountManager: AccountManager, config: OAuthClientConfig) throws {
        guard let account = try accountManager.current() else {
            throw ContextError.noCurrentAccount
        }
        guard let issuer = URL(string: account.issuer) else {
            throw ContextError.invalidIssuer
        }
        let key = try P256.Signing.PrivateKey(rawRepresentation: account.dpopPrivateKeyRaw)
        let http = URLSessionHTTPClient()
        self.account = account
        self.issuer = issuer
        self.sender = DPoPRequestSender(
            http: http, proofBuilder: DPoPProofBuilder(crypto: CryptoKitDPoPProvider(privateKey: key))
        )
        self.metadataResolver = OAuthMetadataResolver(http: http)
        self.config = config
        self.refreshGate = accountManager.refreshGate
        self.accountManager = accountManager
    }

    /// Proactively renew this account's session — independent of any XRPC 401 —
    /// and persist the result. Used on wake from sleep, where the in-memory access
    /// token has likely gone stale, so the next request starts from a fresh token
    /// instead of paying a 401 round-trip (or racing several pollers to refresh).
    /// Routes through the shared `RefreshGate`, so it coalesces with any concurrent
    /// 401-driven refresh on the same single-use token. A nil refresh token is a
    /// no-op. Throws `invalid_grant` when the token is dead, which the caller can
    /// hand to `SessionExpiry.reportIfExpired`.
    func refreshSession() async throws {
        guard let refreshToken = account.refreshToken else { return }
        let refresher = SessionRefresher(
            sender: sender, metadataResolver: metadataResolver, config: config, refreshGate: refreshGate
        )
        let tokens = try await refresher.refresh(issuer: issuer, refreshToken: refreshToken)
        try persist(tokens)
    }

    /// Persist freshly issued tokens after a mid-request refresh; a nil argument
    /// (no refresh happened) is a no-op.
    func persist(_ refreshed: TokenResponse?) throws {
        guard let refreshed else { return }
        try accountManager.updateTokens(
            did: account.did,
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken ?? account.refreshToken,
            scope: refreshed.scope ?? account.scope
        )
    }
}
