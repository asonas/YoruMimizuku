import Foundation

/// Performs OAuth token-endpoint requests (authorization_code and refresh_token
/// grants) over a DPoP-bound channel, reusing `DPoPRequestSender`'s built-in
/// `use_dpop_nonce` retry.
public struct TokenService: Sendable {
    private let sender: DPoPRequestSender

    public init(sender: DPoPRequestSender) {
        self.sender = sender
    }

    /// POST the grant to the server's token endpoint. Accepts 200 as success;
    /// any other status throws `tokenRequestFailed`. A 200 with an undecodable
    /// body throws `malformedDocument`, mirroring the discovery/PAR layers.
    public func requestToken(
        metadata: AuthorizationServerMetadata,
        config: OAuthClientConfig,
        grant: TokenGrant
    ) async throws -> TokenResponse {
        guard !metadata.tokenEndpoint.isEmpty,
              let components = URLComponents(string: metadata.tokenEndpoint),
              components.scheme != nil, components.host != nil,
              let url = components.url else {
            throw OAuthError.malformedDocument("invalid token_endpoint: \(metadata.tokenEndpoint)")
        }
        let body = FormURLEncoder.encode(grant.formParameters(config: config))
        let response = try await sender.send(
            method: .post,
            url: url,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body
        )
        guard response.statusCode == 200 else {
            let oauth = Self.parseErrorBody(response.body)
            // When the body carries no RFC 6749 `error`, surface a short raw-body
            // snippet as the description so a bare/odd 4xx is still diagnosable
            // instead of showing only the status.
            let description = oauth.description ?? Self.rawBodySnippet(response.body)
            throw OAuthError.tokenRequestFailed(
                status: response.statusCode, error: oauth.error, description: description
            )
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: response.body)
        } catch {
            throw OAuthError.malformedDocument("invalid token response")
        }
    }

    /// Best-effort parse of an RFC 6749 token-error body (`{ "error", "error_description" }`).
    /// Returns nils for empty or non-JSON bodies so the caller still reports the status.
    private static func parseErrorBody(_ body: Data) -> (error: String?, description: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return (nil, nil)
        }
        return (json["error"] as? String, json["error_description"] as? String)
    }

    /// A short, single-line snippet of a non-OAuth error body for diagnostics
    /// (whitespace collapsed, capped), or nil when the body carries nothing useful
    /// (empty, or a content-free `{}` / `[]` — those add noise, not signal).
    private static func rawBodySnippet(_ body: Data, limit: Int = 200) -> String? {
        guard let text = String(data: body, encoding: .utf8) else {
            return body.isEmpty ? nil : "<\(body.count) bytes>"
        }
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !collapsed.isEmpty, collapsed != "{}", collapsed != "[]" else { return nil }
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }
}
