import Foundation

/// An OAuth token-endpoint grant. `authorization_code` exchanges the code from
/// the browser redirect (with the PKCE verifier); `refresh_token` renews tokens.
/// Both send `client_id` because the client authenticates with method "none".
public enum TokenGrant: Equatable, Sendable {
    case authorizationCode(code: String, codeVerifier: String)
    case refresh(refreshToken: String)

    /// Ordered form parameters for the token request body.
    public func formParameters(config: OAuthClientConfig) -> [(String, String)] {
        switch self {
        case let .authorizationCode(code, codeVerifier):
            return [
                ("grant_type", "authorization_code"),
                ("code", code),
                ("code_verifier", codeVerifier),
                ("redirect_uri", config.redirectURI),
                ("client_id", config.clientID)
            ]
        case let .refresh(refreshToken):
            return [
                ("grant_type", "refresh_token"),
                ("refresh_token", refreshToken),
                ("client_id", config.clientID)
            ]
        }
    }
}
