import XCTest
@testable import BlueskyCore

final class OAuthClientConfigTests: XCTestCase {
    func testYoruMimizukuProductionConfigMatchesClientMetadata() {
        let config = OAuthClientConfig.yoruMimizuku
        XCTAssertEqual(config.clientID, "https://ason.as/yorumimizuku/client-metadata.json")
        XCTAssertEqual(config.redirectURI, "as.ason:/callback")
        XCTAssertEqual(config.scope, "atproto transition:generic")
    }

    func testCallbackSchemeIsTheRedirectURIScheme() {
        XCTAssertEqual(OAuthClientConfig.yoruMimizuku.callbackScheme, "as.ason")
        let custom = OAuthClientConfig(clientID: "x", redirectURI: "myapp:/cb", scope: "s")
        XCTAssertEqual(custom.callbackScheme, "myapp")
    }
}
