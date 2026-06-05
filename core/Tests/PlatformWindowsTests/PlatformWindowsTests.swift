#if canImport(WinSDK)
import XCTest
@testable import PlatformWindows

final class PlatformWindowsTests: XCTestCase {
    func testBCryptGeneratorReturnsRequestedLength() {
        let generator = BCryptRandomBytesGenerator()
        XCTAssertEqual(generator.bytes(16).count, 16)
        XCTAssertEqual(generator.bytes(32).count, 32)
        XCTAssertEqual(generator.bytes(0).count, 0)
    }

    func testBCryptGeneratorProducesDifferentBytesAcrossCalls() {
        let generator = BCryptRandomBytesGenerator()
        XCTAssertNotEqual(generator.bytes(32), generator.bytes(32))
    }

    func testDPAPISecureStorageRoundTrips() throws {
        let storage = DPAPISecureStorage(service: "as.ason.YoruMimizuku.tests")
        let key = "test.\(UUID().uuidString)"
        defer { try? storage.remove(for: key) }

        XCTAssertNil(try storage.data(for: key))

        let payload = Data("secret-token-value".utf8)
        try storage.set(payload, for: key)
        XCTAssertEqual(try storage.data(for: key), payload)

        try storage.remove(for: key)
        XCTAssertNil(try storage.data(for: key))
    }
}
#endif
