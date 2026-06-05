import Foundation

/// `/.well-known/oauth-protected-resource` on the PDS.
public struct ProtectedResourceMetadata: Decodable, Equatable, Sendable {
    public let authorizationServers: [String]

    enum CodingKeys: String, CodingKey {
        case authorizationServers = "authorization_servers"
    }
}

/// `/.well-known/oauth-authorization-server`.
public struct AuthorizationServerMetadata: Decodable, Equatable, Sendable {
    public let issuer: String
    public let authorizationEndpoint: String
    public let tokenEndpoint: String
    public let pushedAuthorizationRequestEndpoint: String?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case pushedAuthorizationRequestEndpoint = "pushed_authorization_request_endpoint"
    }
}
