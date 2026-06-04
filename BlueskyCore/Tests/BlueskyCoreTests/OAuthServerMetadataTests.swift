import XCTest
@testable import BlueskyCore

final class OAuthServerMetadataTests: XCTestCase {
    func test_decodesProtectedResourceAuthorizationServers() throws {
        let json = Data(#"{"resource":"https://pds.example.com","authorization_servers":["https://bsky.social"]}"#.utf8)

        let metadata = try JSONDecoder().decode(ProtectedResourceMetadata.self, from: json)

        XCTAssertEqual(metadata.authorizationServers, ["https://bsky.social"])
    }

    func test_decodesAuthorizationServerEndpoints() throws {
        let json = Data(#"""
        {
          "issuer": "https://bsky.social",
          "authorization_endpoint": "https://bsky.social/oauth/authorize",
          "token_endpoint": "https://bsky.social/oauth/token",
          "pushed_authorization_request_endpoint": "https://bsky.social/oauth/par"
        }
        """#.utf8)

        let metadata = try JSONDecoder().decode(AuthorizationServerMetadata.self, from: json)

        XCTAssertEqual(metadata.issuer, "https://bsky.social")
        XCTAssertEqual(metadata.authorizationEndpoint, "https://bsky.social/oauth/authorize")
        XCTAssertEqual(metadata.tokenEndpoint, "https://bsky.social/oauth/token")
        XCTAssertEqual(metadata.pushedAuthorizationRequestEndpoint, "https://bsky.social/oauth/par")
    }
}
