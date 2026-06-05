import XCTest
@testable import BlueskyCore

final class OAuthCallbackTests: XCTestCase {
    func testParsesCodeAndState() throws {
        let url = URL(string: "as.ason:/callback?code=auth-code&state=st-1")!
        let callback = try OAuthCallback.parse(url: url)
        XCTAssertEqual(callback.code, "auth-code")
        XCTAssertEqual(callback.state, "st-1")
    }

    func testThrowsAuthorizationDeniedWhenErrorPresent() {
        let url = URL(string: "as.ason:/callback?error=access_denied&error_description=nope")!
        XCTAssertThrowsError(try OAuthCallback.parse(url: url)) { error in
            XCTAssertEqual(
                error as? OAuthError,
                .authorizationDenied(error: "access_denied", description: "nope")
            )
        }
    }

    func testThrowsMissingCodeWhenCodeAbsent() {
        let url = URL(string: "as.ason:/callback?state=st-1")!
        XCTAssertThrowsError(try OAuthCallback.parse(url: url)) { error in
            XCTAssertEqual(error as? OAuthError, .missingAuthorizationCode)
        }
    }
}
