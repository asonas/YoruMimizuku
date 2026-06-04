import XCTest
@testable import BlueskyCore

final class AccountManagerTests: XCTestCase {
    private func loginResult(did: String) -> OAuthLoginResult {
        let json = ##"{"access_token":"atk-\##(did)","token_type":"DPoP","refresh_token":"rtk","sub":"\##(did)"}"##
        // swiftlint:disable:next force_try
        let tokens = try! JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
        return OAuthLoginResult(
            did: did,
            pds: URL(string: "https://pds.example")!,
            authorizationServerIssuer: "https://bsky.social",
            tokens: tokens
        )
    }

    private func makeManager() -> AccountManager {
        AccountManager(store: AccountStore(storage: InMemorySecureStorage()))
    }

    func testAddLoginPersistsAndBecomesCurrent() throws {
        let manager = makeManager()
        let account = try manager.add(
            loginResult: loginResult(did: "did:plc:a"),
            handle: "alice.bsky.social",
            dpopPrivateKeyRaw: Data([0x01])
        )
        XCTAssertEqual(account.did, "did:plc:a")
        XCTAssertEqual(try manager.current()?.did, "did:plc:a")
        XCTAssertEqual(try manager.allDIDs(), ["did:plc:a"])
    }

    func testSecondAddBecomesCurrentAndBothListed() throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: nil, dpopPrivateKeyRaw: Data([0x01]))
        _ = try manager.add(loginResult: loginResult(did: "did:plc:b"), handle: nil, dpopPrivateKeyRaw: Data([0x02]))
        XCTAssertEqual(try manager.current()?.did, "did:plc:b")
        XCTAssertEqual(try manager.allDIDs(), ["did:plc:a", "did:plc:b"])
    }

    func testSwitchChangesCurrent() throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: nil, dpopPrivateKeyRaw: Data([0x01]))
        _ = try manager.add(loginResult: loginResult(did: "did:plc:b"), handle: nil, dpopPrivateKeyRaw: Data([0x02]))
        try manager.switchTo(did: "did:plc:a")
        XCTAssertEqual(try manager.current()?.did, "did:plc:a")
    }

    func testRemoveCurrentClearsCurrent() throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: nil, dpopPrivateKeyRaw: Data([0x01]))
        try manager.remove(did: "did:plc:a")
        XCTAssertNil(try manager.current())
        XCTAssertEqual(try manager.allDIDs(), [])
    }

    func testCurrentIsNilWhenNoAccounts() throws {
        XCTAssertNil(try makeManager().current())
    }

    func testUpdateTokensReplacesTokensAndPreservesOtherFields() throws {
        let manager = makeManager()
        _ = try manager.add(
            loginResult: loginResult(did: "did:plc:a"),
            handle: "alice.bsky.social",
            dpopPrivateKeyRaw: Data([0x09])
        )

        let updated = try manager.updateTokens(
            did: "did:plc:a", accessToken: "atk2", refreshToken: "rtk2", scope: "atproto"
        )

        XCTAssertEqual(updated.accessToken, "atk2")
        let current = try manager.current()
        XCTAssertEqual(current?.accessToken, "atk2")
        XCTAssertEqual(current?.refreshToken, "rtk2")
        XCTAssertEqual(current?.scope, "atproto")
        // Untouched fields survive the update.
        XCTAssertEqual(current?.handle, "alice.bsky.social")
        XCTAssertEqual(current?.dpopPrivateKeyRaw, Data([0x09]))
        // No duplicate index entry was created.
        XCTAssertEqual(try manager.allDIDs(), ["did:plc:a"])
    }

    func testUpdateTokensThrowsForUnknownAccount() {
        let manager = makeManager()
        XCTAssertThrowsError(
            try manager.updateTokens(did: "did:plc:missing", accessToken: "x", refreshToken: nil, scope: nil)
        ) { error in
            XCTAssertEqual(error as? AccountError, .unknownAccount("did:plc:missing"))
        }
    }
}
