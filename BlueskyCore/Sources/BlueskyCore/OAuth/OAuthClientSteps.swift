import Foundation

/// Resolves an account handle/DID to the endpoints needed to start OAuth.
/// Conformed by `OAuthDiscovery`; faked in tests.
public protocol AccountDiscovering: Sendable {
    func discover(account: String) async throws -> OAuthDiscovery.Result
}

/// Performs the Pushed Authorization Request. Conformed by
/// `AuthorizationRequestService`; faked in tests.
public protocol AuthorizationRequesting: Sendable {
    func push(
        metadata: AuthorizationServerMetadata,
        request: AuthorizationRequest
    ) async throws -> PushedAuthorizationResponse
}

/// Performs a token-endpoint request. Conformed by `TokenService`; faked in tests.
public protocol TokenRequesting: Sendable {
    func requestToken(
        metadata: AuthorizationServerMetadata,
        config: OAuthClientConfig,
        grant: TokenGrant
    ) async throws -> TokenResponse
}

extension OAuthDiscovery: AccountDiscovering {}
extension AuthorizationRequestService: AuthorizationRequesting {}
extension TokenService: TokenRequesting {}
