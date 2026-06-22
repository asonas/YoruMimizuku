import Foundation

/// Proactively renews an account's OAuth session via the `refresh_token` grant,
/// independent of any XRPC request. The XRPC services refresh reactively (only
/// after a 401); this lets the app refresh *before* making requests — e.g. when
/// the machine wakes from sleep and the in-memory access token has gone stale.
///
/// The renewal is routed through the shared `RefreshGate`, so a proactive refresh
/// and a concurrent 401-driven refresh on the same single-use refresh token
/// coalesce into one token-endpoint call instead of racing to consume it (the
/// loser would otherwise get `invalid_grant`).
public struct SessionRefresher: Sendable {
    private let sender: DPoPRequestSender
    private let metadataResolver: OAuthMetadataResolver
    private let config: OAuthClientConfig
    private let refreshGate: RefreshGate

    public init(
        sender: DPoPRequestSender,
        metadataResolver: OAuthMetadataResolver,
        config: OAuthClientConfig,
        refreshGate: RefreshGate
    ) {
        self.sender = sender
        self.metadataResolver = metadataResolver
        self.config = config
        self.refreshGate = refreshGate
    }

    /// Renew `refreshToken` against `issuer`'s token endpoint and return the new
    /// tokens. Throws `OAuthError.tokenRequestFailed(_, "invalid_grant", _)` when
    /// the token is dead, which `SessionExpiry.reportIfExpired` recognizes.
    public func refresh(issuer: URL, refreshToken: String) async throws -> TokenResponse {
        let metadataResolver = self.metadataResolver
        let sender = self.sender
        let config = self.config
        return try await refreshGate.refresh(using: refreshToken) {
            let metadata = try await metadataResolver.authorizationServer(issuer: issuer)
            return try await TokenService(sender: sender).requestToken(
                metadata: metadata, config: config, grant: .refresh(refreshToken: refreshToken)
            )
        }
    }
}
