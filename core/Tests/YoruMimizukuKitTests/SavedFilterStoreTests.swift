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

    // MARK: - Store

    @MainActor
    func testLoadsExistingFiltersFromPort() {
        let existing = SavedFilter(name: "Swift", query: "#swift")
        let port = InMemoryFilterStoring(initial: [existing])
        let store = SavedFilterStore(port: port)
        XCTAssertEqual(store.filters, [existing])
    }

    @MainActor
    func testAddAppendsAndPersists() throws {
        let port = InMemoryFilterStoring()
        let store = SavedFilterStore(port: port)

        let added = try XCTUnwrap(store.add(name: "Cats", query: "cats"))

        XCTAssertEqual(store.filters.map(\.id), [added.id])
        XCTAssertEqual(port.saved.last?.map(\.id), [added.id])
    }

    @MainActor
    func testAddRejectsBlankQuery() {
        let port = InMemoryFilterStoring()
        let store = SavedFilterStore(port: port)

        XCTAssertNil(store.add(name: "Empty", query: "   "))
        XCTAssertTrue(store.filters.isEmpty)
        XCTAssertTrue(port.saved.isEmpty)
    }

    @MainActor
    func testAddUsesQueryAsNameWhenNameBlank() throws {
        let port = InMemoryFilterStoring()
        let store = SavedFilterStore(port: port)

        let added = try XCTUnwrap(store.add(name: "  ", query: "#swift"))
        XCTAssertEqual(added.name, "#swift")
    }

    @MainActor
    func testUpdateReplacesByIdAndPersists() throws {
        let original = SavedFilter(name: "Swift", query: "#swift")
        let port = InMemoryFilterStoring(initial: [original])
        let store = SavedFilterStore(port: port)

        var edited = original
        edited.name = "Swift Lang"
        edited.query = "#swiftlang"
        store.update(edited)

        XCTAssertEqual(store.filters.first?.name, "Swift Lang")
        XCTAssertEqual(store.filters.first?.query, "#swiftlang")
        XCTAssertEqual(port.saved.last?.first?.query, "#swiftlang")
    }

    @MainActor
    func testRemoveDeletesByIdAndPersists() {
        let a = SavedFilter(name: "A", query: "a")
        let b = SavedFilter(name: "B", query: "b")
        let port = InMemoryFilterStoring(initial: [a, b])
        let store = SavedFilterStore(port: port)

        store.remove(id: a.id)

        XCTAssertEqual(store.filters.map(\.id), [b.id])
        XCTAssertEqual(port.saved.last?.map(\.id), [b.id])
    }

    @MainActor
    func testStartsEmptyWhenPortLoadThrows() {
        let port = InMemoryFilterStoring(loadError: NSError(domain: "x", code: 1))
        let store = SavedFilterStore(port: port)
        XCTAssertTrue(store.filters.isEmpty)
    }
}

/// In-memory `SavedFilterStoring` fake recording every `save` so tests can assert
/// that mutations persisted. `loadError` simulates a corrupt/missing store file.
private final class InMemoryFilterStoring: SavedFilterStoring, @unchecked Sendable {
    private let initial: [SavedFilter]
    private let loadError: Error?
    private(set) var saved: [[SavedFilter]] = []

    init(initial: [SavedFilter] = [], loadError: Error? = nil) {
        self.initial = initial
        self.loadError = loadError
    }

    func load() throws -> [SavedFilter] {
        if let loadError { throw loadError }
        return initial
    }

    func save(_ filters: [SavedFilter]) throws {
        saved.append(filters)
    }
}
