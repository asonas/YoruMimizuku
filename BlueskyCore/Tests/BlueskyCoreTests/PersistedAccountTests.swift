import XCTest
@testable import BlueskyCore

final class PersistedAccountTests: XCTestCase {
    private func sample() -> PersistedAccount {
        PersistedAccount(
            did: "did:plc:abc",
            handle: "alice.bsky.social",
            pds: URL(string: "https://pds.example")!,
            issuer: "https://bsky.social",
            accessToken: "atk",
            refreshToken: "rtk",
            scope: "atproto transition:generic",
            dpopPrivateKeyRaw: Data([0x01, 0x02, 0x03])
        )
    }

    func testRoundTripsThroughJSON() throws {
        let account = sample()
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(PersistedAccount.self, from: data)
        XCTAssertEqual(decoded, account)
    }

    func testFromLoginResultCopiesFieldsAndKey() throws {
        let tokensJSON = ##"{"access_token":"atk","token_type":"DPoP","refresh_token":"rtk","scope":"atproto","sub":"did:plc:xyz"}"##
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: Data(tokensJSON.utf8))
        let login = OAuthLoginResult(
            did: "did:plc:xyz",
            pds: URL(string: "https://pds.example")!,
            authorizationServerIssuer: "https://bsky.social",
            tokens: tokens
        )
        let account = PersistedAccount(
            loginResult: login,
            handle: "bob.bsky.social",
            dpopPrivateKeyRaw: Data([0xAA])
        )
        XCTAssertEqual(account.did, "did:plc:xyz")
        XCTAssertEqual(account.handle, "bob.bsky.social")
        XCTAssertEqual(account.pds, URL(string: "https://pds.example")!)
        XCTAssertEqual(account.issuer, "https://bsky.social")
        XCTAssertEqual(account.accessToken, "atk")
        XCTAssertEqual(account.refreshToken, "rtk")
        XCTAssertEqual(account.scope, "atproto")
        XCTAssertEqual(account.dpopPrivateKeyRaw, Data([0xAA]))
    }

    func testAccountsIndexRoundTripsThroughJSON() throws {
        let index = AccountsIndex(dids: ["did:plc:a", "did:plc:b"], currentDID: "did:plc:b")
        let data = try JSONEncoder().encode(index)
        XCTAssertEqual(try JSONDecoder().decode(AccountsIndex.self, from: data), index)
    }
}
