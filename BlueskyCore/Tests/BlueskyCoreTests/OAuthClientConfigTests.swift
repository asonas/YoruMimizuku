import XCTest
@testable import BlueskyCore

final class OAuthClientConfigTests: XCTestCase {
    func testHoshidukiyoProductionConfigMatchesClientMetadata() {
        let config = OAuthClientConfig.hoshidukiyo
        XCTAssertEqual(config.clientID, "https://ason.as/hoshidukiyo/client-metadata.json")
        XCTAssertEqual(config.redirectURI, "as.ason:/callback")
        XCTAssertEqual(config.scope, "atproto transition:generic")
    }
}
