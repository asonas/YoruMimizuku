import Foundation
@testable import BlueskyCore

/// Deterministic random source: every byte is 0xAB, so derived verifier/state
/// are reproducible in tests.
struct StubRandomBytesGenerator: RandomBytesGenerator {
    func bytes(_ count: Int) -> Data { Data(repeating: 0xAB, count: count) }
}

struct FakeAccountDiscovering: AccountDiscovering {
    let result: OAuthDiscovery.Result
    func discover(account: String) async throws -> OAuthDiscovery.Result { result }
}

struct FakeAuthorizationRequesting: AuthorizationRequesting {
    let response: PushedAuthorizationResponse
    func push(
        metadata: AuthorizationServerMetadata,
        request: AuthorizationRequest
    ) async throws -> PushedAuthorizationResponse { response }
}

/// Records the grant it was asked to exchange, then returns a canned response.
final class RecordingTokenRequesting: TokenRequesting, @unchecked Sendable {
    let response: TokenResponse
    private(set) var lastGrant: TokenGrant?
    init(response: TokenResponse) { self.response = response }
    func requestToken(
        metadata: AuthorizationServerMetadata,
        config: OAuthClientConfig,
        grant: TokenGrant
    ) async throws -> TokenResponse {
        lastGrant = grant
        return response
    }
}

/// Echoes back a callback URL built from a supplied builder that receives the
/// authorization URL the client tried to open.
final class StubBrowserAuthorizationSession: BrowserAuthorizationSession, @unchecked Sendable {
    let makeCallback: (URL, String) -> URL
    private(set) var openedURL: URL?
    private(set) var openedScheme: String?
    init(makeCallback: @escaping (URL, String) -> URL) { self.makeCallback = makeCallback }
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        openedURL = url
        openedScheme = callbackScheme
        return makeCallback(url, callbackScheme)
    }
}
