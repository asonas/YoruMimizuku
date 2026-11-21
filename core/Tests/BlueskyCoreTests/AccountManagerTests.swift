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


    private static func refreshed(_ access: String, _ refresh: String) -> TokenResponse {
        let json = #"{"access_token":"\#(access)","token_type":"DPoP","refresh_token":"\#(refresh)","sub":"did:plc:a"}"#
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(TokenResponse.self, from: Data(json.utf8))
    }



    // #16: a request that refreshed earlier reports its tokens after a later
    // rotation; its refresh token was already used, and saving it would sign the
    // account out at the next refresh.
    func testUpdateTokensSkipsARefreshTokenAlreadyUsed() async throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: nil, dpopPrivateKeyRaw: Data([0x09]))
        let first = try await manager.refreshGate.refresh(using: "rtk") { Self.refreshed("atk1", "rtk1") }
        let second = try await manager.refreshGate.refresh(using: "rtk1") { Self.refreshed("atk2", "rtk2") }
        try manager.updateTokens(did: "did:plc:a", session: Data([0x09]), accessToken: second.accessToken, refreshToken: second.refreshToken, scope: nil)

        try manager.updateTokens(did: "did:plc:a", session: Data([0x09]), accessToken: first.accessToken, refreshToken: first.refreshToken, scope: nil)

        XCTAssertEqual(try manager.current()?.refreshToken, "rtk2")
        XCTAssertEqual(try manager.current()?.accessToken, "atk2")
    }

    // One request that refreshes twice (a video post: service auth, then the
    // post) saves both rotations.
    func testUpdateTokensSavesEachRotationOfOneRequest() async throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: nil, dpopPrivateKeyRaw: Data([0x09]))
        let first = try await manager.refreshGate.refresh(using: "rtk") { Self.refreshed("atk1", "rtk1") }
        try manager.updateTokens(did: "did:plc:a", session: Data([0x09]), accessToken: first.accessToken, refreshToken: first.refreshToken, scope: nil)
        let second = try await manager.refreshGate.refresh(using: "rtk1") { Self.refreshed("atk2", "rtk2") }

        try manager.updateTokens(did: "did:plc:a", session: Data([0x09]), accessToken: second.accessToken, refreshToken: second.refreshToken, scope: nil)

        XCTAssertEqual(try manager.current()?.refreshToken, "rtk2")
    }

    // A renewal is saved when it happens, so a request that fails after it
    // (and an app quit) does not leave only the used refresh token stored.
    func testARenewalIsSavedWhenItHappens() async throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: nil, dpopPrivateKeyRaw: Data([0x09]))

        _ = try await manager.refreshGate.refresh(using: "rtk") { Self.refreshed("atk1", "rtk1") }

        XCTAssertEqual(try manager.current()?.refreshToken, "rtk1")
        XCTAssertEqual(try manager.current()?.accessToken, "atk1")
    }

    // A request from before a re-login (another DPoP key) must not overwrite
    // the new session's tokens.
    func testUpdateTokensIgnoresAnEarlierSession() throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: nil, dpopPrivateKeyRaw: Data([0x09]))

        try manager.updateTokens(did: "did:plc:a", session: Data([0x01]), accessToken: "atk-old", refreshToken: "rtk-old", scope: nil)

        XCTAssertEqual(try manager.current()?.refreshToken, "rtk")
        XCTAssertEqual(try manager.current()?.accessToken, "atk-did:plc:a")
    }

    // A refresh that does not rotate the refresh token keeps the stored one.
    func testUpdateTokensKeepsTheRefreshTokenWhenNoneIsIssued() throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: nil, dpopPrivateKeyRaw: Data([0x09]))

        try manager.updateTokens(did: "did:plc:a", session: Data([0x09]), accessToken: "atk2", refreshToken: nil, scope: nil)

        XCTAssertEqual(try manager.current()?.accessToken, "atk2")
        XCTAssertEqual(try manager.current()?.refreshToken, "rtk")
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
            did: "did:plc:a", session: Data([0x09]), accessToken: "atk2", refreshToken: "rtk2", scope: "atproto"
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

    func testSummariesListDIDsAndHandlesInOrder() throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: "alice.bsky.social", dpopPrivateKeyRaw: Data([0x01]))
        _ = try manager.add(loginResult: loginResult(did: "did:plc:b"), handle: nil, dpopPrivateKeyRaw: Data([0x02]))

        let summaries = try manager.summaries()

        XCTAssertEqual(summaries.map(\.did), ["did:plc:a", "did:plc:b"])
        XCTAssertEqual(summaries.map(\.handle), ["alice.bsky.social", nil])
    }

    func testRemoveAndAdvanceSwitchesToNextRemaining() throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: nil, dpopPrivateKeyRaw: Data([0x01]))
        _ = try manager.add(loginResult: loginResult(did: "did:plc:b"), handle: nil, dpopPrivateKeyRaw: Data([0x02]))

        // Current is b; removing it advances to the first remaining (a).
        let next = try manager.removeAndAdvance(did: "did:plc:b")

        XCTAssertEqual(next, "did:plc:a")
        XCTAssertEqual(try manager.current()?.did, "did:plc:a")
        XCTAssertEqual(try manager.allDIDs(), ["did:plc:a"])
    }

    func testRemoveAndAdvanceReturnsNilWhenNoneRemain() throws {
        let manager = makeManager()
        _ = try manager.add(loginResult: loginResult(did: "did:plc:a"), handle: nil, dpopPrivateKeyRaw: Data([0x01]))

        let next = try manager.removeAndAdvance(did: "did:plc:a")

        XCTAssertNil(next)
        XCTAssertNil(try manager.current())
        XCTAssertEqual(try manager.allDIDs(), [])
    }

    func testUpdateTokensThrowsForUnknownAccount() {
        let manager = makeManager()
        XCTAssertThrowsError(
            try manager.updateTokens(did: "did:plc:missing", session: Data(), accessToken: "x", refreshToken: nil, scope: nil)
        ) { error in
            XCTAssertEqual(error as? AccountError, .unknownAccount("did:plc:missing"))
        }
    }
}
