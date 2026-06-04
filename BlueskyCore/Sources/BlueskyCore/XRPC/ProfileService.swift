import Foundation

/// Fetches an actor's profile (`app.bsky.actor.getProfile`) from the account's PDS
/// over a DPoP-bound channel. Hoshidukiyo uses it to resolve the signed-in user's
/// avatar for the sidebar. Mirrors `TimelineService`'s auth handling: the
/// `use_dpop_nonce` retry lives in the sender, and an expired access token (401
/// that is not a nonce challenge) is refreshed via `refresh_token` and retried
/// once, returning the freshly issued tokens so the caller can persist them.
///
/// The response is a `profileViewDetailed`; we decode it into `ProfileViewBasic`,
/// whose decoder ignores the detailed-only keys we do not render.
public struct ProfileService: Sendable {
    private let sender: DPoPRequestSender
    private let metadataResolver: OAuthMetadataResolver
    private let config: OAuthClientConfig

    public init(
        sender: DPoPRequestSender,
        metadataResolver: OAuthMetadataResolver,
        config: OAuthClientConfig
    ) {
        self.sender = sender
        self.metadataResolver = metadataResolver
        self.config = config
    }

    /// Fetch `actor`'s profile (a DID or handle). Returns the decoded profile and,
    /// when a refresh occurred, the freshly issued tokens; `refreshed` is nil when
    /// the original access token was still valid.
    public func getProfile(
        pds: URL,
        issuer: URL,
        accessToken: String,
        refreshToken: String?,
        actor: String
    ) async throws -> (response: ProfileViewBasic, refreshed: TokenResponse?) {
        let url = try Self.profileURL(pds: pds, actor: actor)
        let response = try await fetch(url: url, accessToken: accessToken)

        if response.statusCode == 401,
           !DPoPRequestSender.isNonceChallenge(response),
           let refreshToken {
            let tokens = try await refresh(issuer: issuer, refreshToken: refreshToken)
            let retried = try await fetch(url: url, accessToken: tokens.accessToken)
            return (try Self.decode(retried), tokens)
        }

        return (try Self.decode(response), nil)
    }

    private func fetch(url: URL, accessToken: String) async throws -> HTTPResponse {
        try await sender.send(
            method: .get, url: url, accessToken: accessToken,
            headers: ["Accept": "application/json"]
        )
    }

    private func refresh(issuer: URL, refreshToken: String) async throws -> TokenResponse {
        let metadata = try await metadataResolver.authorizationServer(issuer: issuer)
        return try await TokenService(sender: sender).requestToken(
            metadata: metadata, config: config, grant: .refresh(refreshToken: refreshToken)
        )
    }

    static func profileURL(pds: URL, actor: String) throws -> URL {
        let endpoint = pds.appendingPathComponent("xrpc/app.bsky.actor.getProfile")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL("app.bsky.actor.getProfile")
        }
        components.queryItems = [URLQueryItem(name: "actor", value: actor)]
        guard let url = components.url else {
            throw XRPCError.invalidURL("app.bsky.actor.getProfile")
        }
        return url
    }

    static func decode(_ response: HTTPResponse) throws -> ProfileViewBasic {
        guard response.statusCode == 200 else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try JSONDecoder().decode(ProfileViewBasic.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
