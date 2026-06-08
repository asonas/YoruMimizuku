import Foundation

/// Fetches an actor's posts (`app.bsky.feed.getAuthorFeed`) from the account's PDS
/// over a DPoP-bound channel. Mirrors `TimelineService`'s auth handling: the
/// `use_dpop_nonce` retry lives in the sender, and an expired access token (401
/// that is not a nonce challenge) is refreshed via `refresh_token` and retried once,
/// returning the freshly issued tokens so the caller can persist them. The response
/// shape matches `getTimeline`, so it decodes into the existing `TimelineResponse`.
public struct AuthorFeedService: Sendable {
    private let sender: DPoPRequestSender
    private let metadataResolver: OAuthMetadataResolver
    private let config: OAuthClientConfig
    private let refreshGate: RefreshGate

    public init(
        sender: DPoPRequestSender,
        metadataResolver: OAuthMetadataResolver,
        config: OAuthClientConfig,
        refreshGate: RefreshGate = RefreshGate()
    ) {
        self.sender = sender
        self.metadataResolver = metadataResolver
        self.config = config
        self.refreshGate = refreshGate
    }

    /// Fetch a page of `actor`'s feed. `actor` is a DID or handle. Returns the
    /// decoded response and, when a refresh occurred, the freshly issued tokens;
    /// `refreshed` is nil when the original access token was still valid.
    public func getAuthorFeed(
        pds: URL,
        issuer: URL,
        accessToken: String,
        refreshToken: String?,
        actor: String,
        limit: Int = 50,
        cursor: String? = nil,
        filter: String = "posts_and_author_threads"
    ) async throws -> (response: TimelineResponse, refreshed: TokenResponse?) {
        let url = try Self.authorFeedURL(pds: pds, actor: actor, limit: limit, cursor: cursor, filter: filter)
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

    static func authorFeedURL(pds: URL, actor: String, limit: Int, cursor: String?, filter: String) throws -> URL {
        let endpoint = pds.appendingPathComponent("xrpc/app.bsky.feed.getAuthorFeed")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL("app.bsky.feed.getAuthorFeed")
        }
        var items = [
            URLQueryItem(name: "actor", value: actor),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "filter", value: filter)
        ]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = items
        guard let url = components.url else {
            throw XRPCError.invalidURL("app.bsky.feed.getAuthorFeed")
        }
        return url
    }

    static func decode(_ response: HTTPResponse) throws -> TimelineResponse {
        guard response.statusCode == 200 else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try JSONDecoder().decode(TimelineResponse.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
