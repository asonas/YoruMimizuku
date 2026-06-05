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

    // MARK: - subqueries

    private func filter(_ combinator: FilterCombinator, _ terms: [FilterTerm]) -> SavedFilter {
        SavedFilter(name: "n", terms: terms, combinator: combinator)
    }

    func testFragmentRenderingPerKind() {
        XCTAssertEqual(
            filter(.or, [
                FilterTerm(kind: .keyword, value: "  hello world "),
                FilterTerm(kind: .user, value: "@alice.bsky.social"),
                FilterTerm(kind: .hashtag, value: "#swift"),
                FilterTerm(kind: .mention, value: "bob.bsky.social")
            ]).subqueries,
            ["hello world", "from:alice.bsky.social", "#swift", "mentions:bob.bsky.social"]
        )
    }

    func testAndJoinsFragmentsIntoOneQuery() {
        XCTAssertEqual(
            filter(.and, [
                FilterTerm(kind: .hashtag, value: "swift"),
                FilterTerm(kind: .user, value: "alice.bsky.social")
            ]).subqueries,
            ["#swift from:alice.bsky.social"]
        )
    }

    func testOrSplitsFragments() {
        XCTAssertEqual(
            filter(.or, [
                FilterTerm(kind: .user, value: "alice.bsky.social"),
                FilterTerm(kind: .user, value: "bob.bsky.social")
            ]).subqueries,
            ["from:alice.bsky.social", "from:bob.bsky.social"]
        )
    }

    func testBlankTermsAreDropped() {
        XCTAssertEqual(
            filter(.and, [
                FilterTerm(kind: .keyword, value: "   "),
                FilterTerm(kind: .hashtag, value: "swift")
            ]).subqueries,
            ["#swift"]
        )
    }

    func testAllBlankYieldsEmpty() {
        XCTAssertTrue(filter(.or, [FilterTerm(kind: .keyword, value: "  ")]).subqueries.isEmpty)
        XCTAssertTrue(filter(.and, []).subqueries.isEmpty)
    }

    func testPrefixOnlyValuesYieldNoFragment() {
        // A value of just "@" or "#" must not produce a degenerate fragment.
        XCTAssertTrue(filter(.or, [
            FilterTerm(kind: .user, value: "@"),
            FilterTerm(kind: .mention, value: " @ "),
            FilterTerm(kind: .hashtag, value: "#")
        ]).subqueries.isEmpty)
    }

    func testFallbackNameAndSummary() {
        let or = filter(.or, [
            FilterTerm(kind: .user, value: "alice.bsky.social"),
            FilterTerm(kind: .user, value: "bob.bsky.social")
        ])
        XCTAssertEqual(or.fallbackName, "from:alice.bsky.social | from:bob.bsky.social")
        XCTAssertEqual(or.summary, "OR: from:alice.bsky.social, from:bob.bsky.social")

        let and = filter(.and, [
            FilterTerm(kind: .hashtag, value: "swift"),
            FilterTerm(kind: .user, value: "alice.bsky.social")
        ])
        XCTAssertEqual(and.fallbackName, "#swift from:alice.bsky.social")
        XCTAssertEqual(and.summary, "#swift from:alice.bsky.social")
    }
}
