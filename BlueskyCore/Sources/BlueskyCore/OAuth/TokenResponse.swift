import Foundation

/// Successful response from the OAuth token endpoint (both authorization_code
/// and refresh_token grants). `sub` is the account DID. `tokenType` is "DPoP"
/// for atproto. `refreshToken`/`expiresIn`/`scope` may be omitted by the server.
public struct TokenResponse: Decodable, Equatable, Sendable {
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
