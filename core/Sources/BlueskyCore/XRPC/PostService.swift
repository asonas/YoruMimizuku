import Foundation

/// Writes posts to the account's PDS over a DPoP-bound channel: uploads image
/// blobs (`com.atproto.repo.uploadBlob`) and creates the post record
/// (`com.atproto.repo.createRecord` / `app.bsky.feed.post`). Mirrors the auth
/// handling of `TimelineService`/`ProfileService`: the `use_dpop_nonce` retry lives
/// in the sender, and a 401 that is not a nonce challenge refreshes via
/// `refresh_token` and retries once. Because a single createPost makes several
/// requests, the latest refreshed tokens are threaded forward and returned so the
/// caller can persist them.
public struct PostService: Sendable {
    private let sender: DPoPRequestSender
    private let metadataResolver: OAuthMetadataResolver
    private let config: OAuthClientConfig

    public init(sender: DPoPRequestSender, metadataResolver: OAuthMetadataResolver, config: OAuthClientConfig) {
        self.sender = sender
        self.metadataResolver = metadataResolver
        self.config = config
    }

    public func uploadBlob(
        pds: URL, issuer: URL, accessToken: String, refreshToken: String?,
        data: Data, mimeType: String
    ) async throws -> (blob: BlobRef, refreshed: TokenResponse?) {
        let url = pds.appendingPathComponent("xrpc/com.atproto.repo.uploadBlob")
        let headers = ["Content-Type": mimeType, "Accept": "application/json"]
        let outcome = try await perform(method: .post, url: url, headers: headers, body: data,
                                        issuer: issuer, accessToken: accessToken, refreshToken: refreshToken)
        let decoded: UploadBlobResponse = try Self.decode(outcome.response)
        return (decoded.blob, outcome.refreshed)
    }

    /// One authorized request with a 401→refresh→retry-once. Returns the response
    /// and, when a refresh occurred, the freshly issued tokens.
    func perform(
        method: HTTPMethod, url: URL, headers: [String: String], body: Data?,
        issuer: URL, accessToken: String, refreshToken: String?
    ) async throws -> (response: HTTPResponse, refreshed: TokenResponse?) {
        let response = try await sender.send(method: method, url: url, accessToken: accessToken,
                                             headers: headers, body: body)
        if response.statusCode == 401, !DPoPRequestSender.isNonceChallenge(response), let refreshToken {
            let tokens = try await refresh(issuer: issuer, refreshToken: refreshToken)
            let retried = try await sender.send(method: method, url: url, accessToken: tokens.accessToken,
                                                headers: headers, body: body)
            return (retried, tokens)
        }
        return (response, nil)
    }

    private func refresh(issuer: URL, refreshToken: String) async throws -> TokenResponse {
        let metadata = try await metadataResolver.authorizationServer(issuer: issuer)
        return try await TokenService(sender: sender).requestToken(
            metadata: metadata, config: config, grant: .refresh(refreshToken: refreshToken)
        )
    }

    static func decode<T: Decodable>(_ response: HTTPResponse) throws -> T {
        guard (200..<300).contains(response.statusCode) else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
