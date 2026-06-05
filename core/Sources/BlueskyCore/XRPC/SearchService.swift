import Foundation

/// Fetches search results (`app.bsky.feed.searchPosts`) from the account's PDS
/// over a DPoP-bound channel. Mirrors `TimelineService`: the injected
/// `DPoPRequestSender` carries the access token and handles the `use_dpop_nonce`
/// retry; on an expired access token (a 401 that is not a nonce challenge) it
/// refreshes via `refresh_token` and retries once, returning the freshly issued
/// tokens so the caller can persist them.
public struct SearchService: Sendable {
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

    /// Fetch a page of search results for `query`. Returns the decoded response
    /// and, when a refresh occurred, the freshly issued tokens (nil otherwise).
    public func searchPosts(
        pds: URL,
        issuer: URL,
        accessToken: String,
        refreshToken: String?,
        query: String,
        limit: Int = 25,
        cursor: String? = nil
    ) async throws -> (response: SearchResponse, refreshed: TokenResponse?) {
        let url = try Self.searchURL(pds: pds, query: query, limit: limit, cursor: cursor)
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

    static func searchURL(pds: URL, query: String, limit: Int, cursor: String?) throws -> URL {
        let endpoint = pds.appendingPathComponent("xrpc/app.bsky.feed.searchPosts")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL("app.bsky.feed.searchPosts")
        }
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = items
        guard let url = components.url else {
            throw XRPCError.invalidURL("app.bsky.feed.searchPosts")
        }
        return url
    }

    static func decode(_ response: HTTPResponse) throws -> SearchResponse {
        guard response.statusCode == 200 else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try JSONDecoder().decode(SearchResponse.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
