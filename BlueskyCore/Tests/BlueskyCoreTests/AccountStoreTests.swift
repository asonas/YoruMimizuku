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
}
