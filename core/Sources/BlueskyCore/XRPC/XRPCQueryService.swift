import Foundation

/// Runs any XRPC query (an HTTP GET) against the account's PDS over a DPoP-bound
/// channel and decodes the JSON body. It has the same auth handling as the
/// per-endpoint services: the `use_dpop_nonce` retry lives in the sender, and an
/// expired access token (401 that is not a nonce challenge) is refreshed once and
/// retried, returning the new tokens so the caller can persist them. New read
/// endpoints use this instead of copying that handling into another service.
public struct XRPCQueryService: Sendable {
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

    /// Query `nsid` with `parameters` (repeat a name for an array parameter) and
    /// decode the response as `Response`. `refreshed` is nil when the original
    /// access token was still valid.
    public func query<Response: Decodable>(
        _ nsid: String,
        parameters: [(String, String)],
        pds: URL,
        issuer: URL,
        accessToken: String,
        refreshToken: String?
    ) async throws -> (response: Response, refreshed: TokenResponse?) {
        let url = try Self.url(pds: pds, nsid: nsid, parameters: parameters)
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

    static func url(pds: URL, nsid: String, parameters: [(String, String)]) throws -> URL {
        let endpoint = pds.appendingPathComponent("xrpc/\(nsid)")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL(nsid)
        }
        if !parameters.isEmpty {
            components.queryItems = parameters.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else { throw XRPCError.invalidURL(nsid) }
        return url
    }

    static func decode<Response: Decodable>(_ response: HTTPResponse) throws -> Response {
        guard response.statusCode == 200 else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
