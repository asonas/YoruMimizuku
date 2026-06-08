import Foundation

/// Fetches a single post's thread (`app.bsky.feed.getPostThread`) over a
/// DPoP-bound channel so the UI can climb the reply tree. Mirrors
/// `TimelineService`'s auth handling: the `use_dpop_nonce` retry lives in the
/// sender, and an expired access token (401 that is not a nonce challenge) is
/// refreshed via `refresh_token` and retried once, returning the new tokens.
public struct ThreadService: Sendable {
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

    /// Fetch the thread for `uri`, returning the focused post with its full ancestor
    /// chain AND its descendant reply tree. Returns freshly issued tokens when a
    /// refresh occurred so the caller can persist them; `refreshed` is nil when the
    /// access token was still valid.
    public func getPostThread(
        pds: URL,
        issuer: URL,
        accessToken: String,
        refreshToken: String?,
        uri: String
    ) async throws -> (response: ThreadResponse, refreshed: TokenResponse?) {
        let url = try Self.threadURL(pds: pds, uri: uri)
        let response = try await fetch(url: url, accessToken: accessToken)

        if response.statusCode == 401,
           !DPoPRequestSender.isNonceChallenge(response),
           let refreshToken {
            let tokens = try await refresh(issuer: issuer, refreshToken: refreshToken)
            let retried = try await fetch(url: url, accessToken: tokens.accessToken)
            return (try Self.decodeThread(retried), tokens)
        }

        return (try Self.decodeThread(response), nil)
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

    static func threadURL(pds: URL, uri: String) throws -> URL {
        let endpoint = pds.appendingPathComponent("xrpc/app.bsky.feed.getPostThread")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL("app.bsky.feed.getPostThread")
        }
        // The conversation view climbs the full ancestor chain above the focused
        // post AND renders a few levels of descendants below it, so request both:
        // the lexicon's default ancestor height and a descendant depth deep enough
        // to feed the rendered child tree (3 levels) plus its "さらに表示" cue.
        components.queryItems = [
            URLQueryItem(name: "uri", value: uri),
            URLQueryItem(name: "depth", value: "6"),
            URLQueryItem(name: "parentHeight", value: "80")
        ]
        guard let url = components.url else {
            throw XRPCError.invalidURL("app.bsky.feed.getPostThread")
        }
        return url
    }

    static func decodeThread(_ response: HTTPResponse) throws -> ThreadResponse {
        guard response.statusCode == 200 else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try JSONDecoder().decode(ThreadResponse.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
