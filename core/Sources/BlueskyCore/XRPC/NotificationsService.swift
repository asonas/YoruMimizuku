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
        let (response, refreshed) = try await request(
            url: url, issuer: issuer, accessToken: accessToken, refreshToken: refreshToken
        )
        return (try Self.decode(response), refreshed)
    }

    public func getUnreadCount(
        pds: URL, issuer: URL, accessToken: String, refreshToken: String?
    ) async throws -> (count: Int, refreshed: TokenResponse?) {
        struct Output: Decodable { let count: Int }
        let (response, refreshed) = try await request(
            url: pds.appendingPathComponent("xrpc/app.bsky.notification.getUnreadCount"),
            issuer: issuer, accessToken: accessToken, refreshToken: refreshToken
        )
        try Self.checkStatus(response)
        let output = try JSONDecoder().decode(Output.self, from: response.body)
        return (output.count, refreshed)
    }

    public func updateSeen(
        pds: URL, issuer: URL, accessToken: String, refreshToken: String?, through date: Date
    ) async throws -> TokenResponse? {
        let seenAt = date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        let (response, refreshed) = try await request(
            url: pds.appendingPathComponent("xrpc/app.bsky.notification.updateSeen"),
            issuer: issuer, accessToken: accessToken, refreshToken: refreshToken,
            method: .post, body: try JSONEncoder().encode(["seenAt": seenAt])
        )
        try Self.checkStatus(response)
        return refreshed
    }

    private func request(
        url: URL, issuer: URL, accessToken: String, refreshToken: String?,
        method: HTTPMethod = .get, body: Data? = nil
    ) async throws -> (HTTPResponse, TokenResponse?) {
        func send(_ token: String) async throws -> HTTPResponse {
            var headers = ["Accept": "application/json"]
            if body != nil { headers["Content-Type"] = "application/json" }
            return try await sender.send(method: method, url: url, accessToken: token, headers: headers, body: body)
        }

        let response = try await send(accessToken)
        guard response.statusCode == 401, !DPoPRequestSender.isNonceChallenge(response), let refreshToken else {
            return (response, nil)
        }
        let tokens = try await refresh(issuer: issuer, refreshToken: refreshToken)
        return (try await send(tokens.accessToken), tokens)
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

    static func notificationsURL(pds: URL, limit: Int, cursor: String?) throws -> URL {
        let endpoint = pds.appendingPathComponent("xrpc/app.bsky.notification.listNotifications")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL("app.bsky.notification.listNotifications")
        }
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        // Explicitly opt out of priority-only filtering: when the parameter is
        // omitted the AppView falls back to the account-level priority setting,
        // which silently drops notifications (such as replies) from accounts the
        // viewer does not follow. YoruMimizuku has no priority mode, so it always
        // asks for the full stream.
        items.append(URLQueryItem(name: "priority", value: "false"))
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = items
        guard let url = components.url else {
            throw XRPCError.invalidURL("app.bsky.notification.listNotifications")
        }
        return url
    }

    private static func checkStatus(_ response: HTTPResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
    }

    static func decode(_ response: HTTPResponse) throws -> ListNotificationsResponse {
        try checkStatus(response)
        do {
            return try JSONDecoder().decode(ListNotificationsResponse.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
