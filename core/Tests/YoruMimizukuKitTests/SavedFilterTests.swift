import XCTest
@testable import YoruMimizukuKit

final class SavedFilterTests: XCTestCase {
    // MARK: - Migration / Codable

    func testLegacyQueryDecodesToSingleKeywordTermAnd() throws {
        let legacy = Data(##"""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Swift",
          "query": "#swift from:alice.bsky.social",
          "createdAt": 1000
        }
        """##.utf8)
        let decoder = JSONDecoder()
        let filter = try decoder.decode(SavedFilter.self, from: legacy)

        XCTAssertEqual(filter.name, "Swift")
        XCTAssertEqual(filter.combinator, .and)
        XCTAssertEqual(filter.terms.count, 1)
        XCTAssertEqual(filter.terms[0].kind, .keyword)
        XCTAssertEqual(filter.terms[0].value, "#swift from:alice.bsky.social")
    }

    func testNewShapeRoundTrips() throws {
        let filter = SavedFilter(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Two users",
            terms: [
                FilterTerm(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, kind: .user, value: "alice.bsky.social"),
                FilterTerm(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, kind: .user, value: "bob.bsky.social")
            ],
            combinator: .or,
            createdAt: Date(timeIntervalSince1970: 2000)
        )
        let data = try JSONEncoder().encode(filter)
        let decoded = try JSONDecoder().decode(SavedFilter.self, from: data)
        XCTAssertEqual(decoded, filter)
    }

    func testEncodedShapeOmitsLegacyQueryKey() throws {
        let filter = SavedFilter(name: "x", terms: [FilterTerm(kind: .keyword, value: "y")], combinator: .and)
        let data = try JSONEncoder().encode(filter)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["terms"])
        XCTAssertNil(object?["query"], "legacy query key must not be written")
    }
}
