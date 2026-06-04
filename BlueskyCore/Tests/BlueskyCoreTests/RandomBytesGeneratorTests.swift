import XCTest
@testable import BlueskyCore

final class RandomBytesGeneratorTests: XCTestCase {
    func testSecGeneratorReturnsRequestedLength() {
        let generator = SecRandomBytesGenerator()
        XCTAssertEqual(generator.bytes(16).count, 16)
        XCTAssertEqual(generator.bytes(32).count, 32)
        XCTAssertEqual(generator.bytes(0).count, 0)
    }

    func testSecGeneratorProducesDifferentBytesAcrossCalls() {
        let generator = SecRandomBytesGenerator()
        // 32 random bytes colliding across two calls is cryptographically negligible.
        XCTAssertNotEqual(generator.bytes(32), generator.bytes(32))
    }
}
