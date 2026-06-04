import XCTest
@testable import BlueskyCore

final class AccountStoreTests: XCTestCase {
    func testInMemoryStorageRoundTrips() throws {
        let storage: SecureStorage = InMemorySecureStorage()
        XCTAssertNil(try storage.data(for: "k"))
        try storage.set(Data([1, 2, 3]), for: "k")
        XCTAssertEqual(try storage.data(for: "k"), Data([1, 2, 3]))
        try storage.remove(for: "k")
        XCTAssertNil(try storage.data(for: "k"))
    }

    private func sampleAccount(did: String) -> PersistedAccount {
        PersistedAccount(
            did: did,
            handle: nil,
            pds: URL(string: "https://pds.example")!,
            issuer: "https://bsky.social",
            accessToken: "atk-\(did)",
            refreshToken: "rtk",
            scope: nil,
            dpopPrivateKeyRaw: Data([0x01])
        )
    }

    func testSaveAndLoadAccount() throws {
        let store = AccountStore(storage: InMemorySecureStorage())
        XCTAssertNil(try store.account(did: "did:plc:a"))
        try store.save(sampleAccount(did: "did:plc:a"))
        XCTAssertEqual(try store.account(did: "did:plc:a")?.accessToken, "atk-did:plc:a")
    }

    func testSaveAddsToIndexWithoutDuplicates() throws {
        let store = AccountStore(storage: InMemorySecureStorage())
        try store.save(sampleAccount(did: "did:plc:a"))
        try store.save(sampleAccount(did: "did:plc:a")) // same did again
        try store.save(sampleAccount(did: "did:plc:b"))
        XCTAssertEqual(try store.index().dids, ["did:plc:a", "did:plc:b"])
    }

    func testSetAndGetCurrentDID() throws {
        let store = AccountStore(storage: InMemorySecureStorage())
        try store.save(sampleAccount(did: "did:plc:a"))
        XCTAssertNil(try store.index().currentDID)
        try store.setCurrent(did: "did:plc:a")
        XCTAssertEqual(try store.index().currentDID, "did:plc:a")
    }

    func testSetCurrentToUnknownDIDThrows() throws {
        let store = AccountStore(storage: InMemorySecureStorage())
        XCTAssertThrowsError(try store.setCurrent(did: "did:plc:missing")) { error in
            XCTAssertEqual(error as? AccountError, .unknownAccount("did:plc:missing"))
        }
    }

    func testRemoveDeletesAccountAndIndexEntryAndClearsCurrent() throws {
        let store = AccountStore(storage: InMemorySecureStorage())
        try store.save(sampleAccount(did: "did:plc:a"))
        try store.save(sampleAccount(did: "did:plc:b"))
        try store.setCurrent(did: "did:plc:a")
        try store.remove(did: "did:plc:a")
        XCTAssertNil(try store.account(did: "did:plc:a"))
        XCTAssertEqual(try store.index().dids, ["did:plc:b"])
        XCTAssertNil(try store.index().currentDID) // current cleared when removed
    }
}
