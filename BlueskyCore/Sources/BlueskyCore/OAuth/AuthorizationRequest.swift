import Foundation

/// Successful PAR response: an opaque `request_uri` the authorization endpoint
/// later resolves, plus its lifetime in seconds.
public struct PushedAuthorizationResponse: Decodable, Equatable, Sendable {
    public let requestURI: String
    public let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case requestURI = "request_uri"
        case expiresIn = "expires_in"
    }
}

/// The inputs to an OAuth authorization, ready to be serialized as PAR form
/// parameters. `state` is an opaque CSRF token the caller supplies; generate
/// one with `generateState`.
public struct AuthorizationRequest: Equatable, Sendable {
    public let config: OAuthClientConfig
    public let pkce: PKCE
    public let state: String
    public let loginHint: String?

    public init(config: OAuthClientConfig, pkce: PKCE, state: String, loginHint: String? = nil) {
        self.config = config
        self.pkce = pkce
        self.state = state
        self.loginHint = loginHint
    }

    /// Ordered form parameters for the PAR body. `login_hint` is included only
    /// when present.
    public func formParameters() -> [(String, String)] {
        var params: [(String, String)] = [
            ("response_type", "code"),
            ("client_id", config.clientID),
            ("redirect_uri", config.redirectURI),
            ("scope", config.scope),
            ("state", state),
            ("code_challenge", pkce.codeChallenge),
            ("code_challenge_method", pkce.codeChallengeMethod)
        ]
        if let loginHint {
            params.append(("login_hint", loginHint))
        }
        return params
    }

    /// Generate an opaque state value as base64url of 16 random bytes.
    /// `randomBytes` is injected for testability (production passes the OS RNG).
    public static func generateState(randomBytes: (Int) -> Data) -> String {
        Base64URL.encode(randomBytes(16))
    }
}
