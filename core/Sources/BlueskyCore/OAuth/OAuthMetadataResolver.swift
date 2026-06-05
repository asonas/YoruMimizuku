import Foundation

/// Resolves the OAuth well-known documents: the PDS's protected-resource
/// metadata and the authorization server's metadata.
public struct OAuthMetadataResolver: Sendable {
    private let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    public func protectedResource(pds: URL) async throws -> ProtectedResourceMetadata {
        let url = pds.appendingPathComponent(".well-known/oauth-protected-resource")
        return try await getDiscoveryJSON(url, http: http)
    }

    public func authorizationServer(issuer: URL) async throws -> AuthorizationServerMetadata {
        let url = issuer.appendingPathComponent(".well-known/oauth-authorization-server")
        return try await getDiscoveryJSON(url, http: http)
    }
}
