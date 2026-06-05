import XCTest
@testable import YoruMimizukuKit

final class SavedFilterStoreTests: XCTestCase {
    func testSavedFilterIsCodableRoundTrips() throws {
        let filter = SavedFilter(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Swift",
            query: "#swift",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let data = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(SavedFilter.self, from: data)
        XCTAssertEqual(decoded, filter)
    }
}
