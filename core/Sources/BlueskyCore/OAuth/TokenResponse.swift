import Foundation

/// Successful response from the OAuth token endpoint (both authorization_code
/// and refresh_token grants). `sub` is the account DID. `tokenType` is "DPoP"
/// for atproto. `refreshToken`/`expiresIn`/`scope` may be omitted by the server.
public struct TokenResponse: Decodable, Equatable, Sendable {
    /// Check that tokens from a login are for `expectedDID`, the account resolved
    /// when the login started, and grant the `atproto` scope.
    public func verifyLogin(expectedDID: String) throws {
        guard sub == expectedDID else { throw OAuthError.subjectMismatch(expected: expectedDID, actual: sub) }
        let scopes = (scope ?? "").split(separator: " ")
        guard scopes.contains("atproto") else { throw OAuthError.missingAtprotoScope }
    }

    public let accessToken: String
    public let tokenType: String
    public let refreshToken: String?
    public let expiresIn: Int?
    public let scope: String?
    public let sub: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case sub
    }
}
