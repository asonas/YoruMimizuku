import Foundation

/// Performs the Pushed Authorization Request (PAR) over a DPoP-bound channel and
/// builds the browser authorization URL from the returned `request_uri`.
public struct AuthorizationRequestService: Sendable {
    private let sender: DPoPRequestSender

    public init(sender: DPoPRequestSender) {
        self.sender = sender
    }

    /// POST the authorization parameters to the server's PAR endpoint.
    /// Accepts 200 or 201 as success; any other status throws.
    public func push(
        metadata: AuthorizationServerMetadata,
        request: AuthorizationRequest
    ) async throws -> PushedAuthorizationResponse {
        guard let endpoint = metadata.pushedAuthorizationRequestEndpoint,
              let url = URL(string: endpoint) else {
            throw OAuthError.pushedAuthorizationRequestNotSupported(issuer: metadata.issuer)
        }
        let body = FormURLEncoder.encode(request.formParameters())
        let response = try await sender.send(
            method: .post,
            url: url,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body
        )
        guard response.statusCode == 200 || response.statusCode == 201 else {
            throw OAuthError.authorizationRequestFailed(status: response.statusCode)
        }
        return try JSONDecoder().decode(PushedAuthorizationResponse.self, from: response.body)
    }

    /// Build the browser authorization URL: the server's authorization endpoint
    /// plus `client_id` and the PAR-issued `request_uri`. Per atproto, these are
    /// the only two query parameters needed once PAR has been performed.
    public static func authorizationURL(
        metadata: AuthorizationServerMetadata,
        config: OAuthClientConfig,
        requestURI: String
    ) throws -> URL {
        guard !metadata.authorizationEndpoint.isEmpty,
              var components = URLComponents(string: metadata.authorizationEndpoint),
              components.scheme != nil, components.host != nil else {
            throw OAuthError.malformedDocument(
                "invalid authorization_endpoint: \(metadata.authorizationEndpoint)"
            )
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "request_uri", value: requestURI)
        ]
        guard let url = components.url else {
            throw OAuthError.malformedDocument("could not build authorization URL")
        }
        return url
    }
}
