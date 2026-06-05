import Foundation

/// Fetches the account's notifications (`app.bsky.notification.listNotifications`)
/// from its PDS over a DPoP-bound channel. Mirrors `TimelineService`'s auth
/// handling: the `use_dpop_nonce` retry lives in the sender, and an expired access
/// token (401 that is not a nonce challenge) is refreshed via `refresh_token` and
/// retried once, returning the freshly issued tokens so the caller can persist them.
public struct NotificationsService: Sendable {
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

    /// Fetch a page of notifications. Returns the decoded response and, when a
    /// refresh occurred, the freshly issued tokens; `refreshed` is nil when the
    /// original access token was still valid.
    public func listNotifications(
        pds: URL,
        issuer: URL,
        accessToken: String,
        refreshToken: String?,
        limit: Int = 50,
        cursor: String? = nil
    ) async throws -> (response: ListNotificationsResponse, refreshed: TokenResponse?) {
        let url = try Self.notificationsURL(pds: pds, limit: limit, cursor: cursor)
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

    static func notificationsURL(pds: URL, limit: Int, cursor: String?) throws -> URL {
        let endpoint = pds.appendingPathComponent("xrpc/app.bsky.notification.listNotifications")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL("app.bsky.notification.listNotifications")
        }
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = items
        guard let url = components.url else {
            throw XRPCError.invalidURL("app.bsky.notification.listNotifications")
        }
        return url
    }

    static func decode(_ response: HTTPResponse) throws -> ListNotificationsResponse {
        guard response.statusCode == 200 else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try JSONDecoder().decode(ListNotificationsResponse.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
