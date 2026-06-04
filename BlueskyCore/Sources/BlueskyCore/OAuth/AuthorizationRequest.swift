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
