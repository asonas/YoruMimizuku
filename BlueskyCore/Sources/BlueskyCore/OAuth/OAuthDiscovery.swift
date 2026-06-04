import Foundation

/// Orchestrates the full OAuth discovery chain for an account:
/// handle/DID → DID → PDS → authorization server metadata.
public struct OAuthDiscovery: Sendable {
    /// The resolved endpoints needed to start an OAuth authorization for an account.
    public struct Result: Equatable, Sendable {
        public let did: String
        public let pds: URL
        public let authorizationServerIssuer: String
        public let metadata: AuthorizationServerMetadata
    }

    private let identity: IdentityResolver
    private let metadataResolver: OAuthMetadataResolver

    public init(http: HTTPClient) {
        self.identity = IdentityResolver(http: http)
        self.metadataResolver = OAuthMetadataResolver(http: http)
    }

    public init(identity: IdentityResolver, metadataResolver: OAuthMetadataResolver) {
        self.identity = identity
        self.metadataResolver = metadataResolver
    }

    public func discover(account handleOrDID: String) async throws -> Result {
        let did = try await identity.resolveHandleToDID(handleOrDID)
        let pds = try await identity.resolveDIDToPDS(did)
        let protectedResource = try await metadataResolver.protectedResource(pds: pds)
        guard let issuer = protectedResource.authorizationServers.first else {
            throw OAuthError.malformedDocument("no authorization_servers listed")
        }
        guard let issuerURL = URL(string: issuer) else {
            throw OAuthError.malformedDocument("invalid authorization server issuer: \(issuer)")
        }
        let metadata = try await metadataResolver.authorizationServer(issuer: issuerURL)
        return Result(
            did: did,
            pds: pds,
            authorizationServerIssuer: issuer,
            metadata: metadata
        )
    }
}
