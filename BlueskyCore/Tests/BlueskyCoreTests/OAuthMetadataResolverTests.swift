import XCTest
@testable import BlueskyCore

final class OAuthMetadataResolverTests: XCTestCase {
    func test_protectedResource_fetchesWellKnownOnPDS() async throws {
        let http = RoutingHTTPClient.json([
            (
                url: "https://pds.example.com/.well-known/oauth-protected-resource",
                body: #"{"resource":"https://pds.example.com","authorization_servers":["https://bsky.social"]}"#
            )
        ])
        let resolver = OAuthMetadataResolver(http: http)

        let metadata = try await resolver.protectedResource(pds: URL(string: "https://pds.example.com")!)

        XCTAssertEqual(metadata.authorizationServers, ["https://bsky.social"])
    }

    func test_authorizationServer_fetchesWellKnownOnIssuer() async throws {
        let http = RoutingHTTPClient.json([
            (
                url: "https://bsky.social/.well-known/oauth-authorization-server",
                body: #"{"issuer":"https://bsky.social","authorization_endpoint":"https://bsky.social/oauth/authorize","token_endpoint":"https://bsky.social/oauth/token","pushed_authorization_request_endpoint":"https://bsky.social/oauth/par"}"#
            )
        ])
        let resolver = OAuthMetadataResolver(http: http)

        let metadata = try await resolver.authorizationServer(issuer: URL(string: "https://bsky.social")!)

        XCTAssertEqual(metadata.tokenEndpoint, "https://bsky.social/oauth/token")
        XCTAssertEqual(metadata.pushedAuthorizationRequestEndpoint, "https://bsky.social/oauth/par")
    }
}
