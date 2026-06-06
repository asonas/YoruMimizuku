import Foundation

/// Fetches hydrated posts by URI (`app.bsky.feed.getPosts`) over a DPoP-bound
/// channel. YoruMimizuku uses it to resolve the target post of a like/repost
/// notification so the UI can show which post a reaction was about. Mirrors
/// `ProfileService`'s auth handling: the `use_dpop_nonce` retry lives in the
/// sender, and an expired access token (401 that is not a nonce challenge) is
/// refreshed via `refresh_token` and retried once, returning the new tokens.
public struct PostsService: Sendable {
    /// The lexicon caps `getPosts` at 25 URIs per call; callers must batch.
    public static let maxURIsPerRequest = 25

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

    /// Fetch the posts for `uris` (at most `maxURIsPerRequest`). An empty `uris`
    /// short-circuits to an empty response without a network call. Returns freshly
    /// issued tokens when a refresh occurred so the caller can persist them.
    public func getPosts(
        pds: URL,
        issuer: URL,
        accessToken: String,
        refreshToken: String?,
        uris: [String]
    ) async throws -> (response: GetPostsResponse, refreshed: TokenResponse?) {
        guard !uris.isEmpty else {
            return (GetPostsResponse(posts: []), nil)
        }

        let url = try Self.postsURL(pds: pds, uris: uris)
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

    static func postsURL(pds: URL, uris: [String]) throws -> URL {
        let endpoint = pds.appendingPathComponent("xrpc/app.bsky.feed.getPosts")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL("app.bsky.feed.getPosts")
        }
        components.queryItems = uris.map { URLQueryItem(name: "uris", value: $0) }
        guard let url = components.url else {
            throw XRPCError.invalidURL("app.bsky.feed.getPosts")
        }
        return url
    }

    static func decode(_ response: HTTPResponse) throws -> GetPostsResponse {
        guard response.statusCode == 200 else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try JSONDecoder().decode(GetPostsResponse.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
