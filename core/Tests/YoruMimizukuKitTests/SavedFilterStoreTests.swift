import XCTest
@testable import YoruMimizukuKit

final class SavedFilterStoreTests: XCTestCase {
    @MainActor
    func testLoadsExistingFiltersFromPort() {
        let existing = SavedFilter(name: "Swift", terms: [FilterTerm(kind: .hashtag, value: "swift")], combinator: .and)
        let port = InMemoryFilterStoring(initial: [existing])
        let store = SavedFilterStore(port: port)
        XCTAssertEqual(store.filters, [existing])
    }

    @MainActor
    func testAddAppendsAndPersists() throws {
        let port = InMemoryFilterStoring()
        let store = SavedFilterStore(port: port)

        let added = try XCTUnwrap(store.add(
            name: "Cats", terms: [FilterTerm(kind: .keyword, value: "cats")], combinator: .and
        ))

        XCTAssertEqual(store.filters.map(\.id), [added.id])
        XCTAssertEqual(port.saved.last?.map(\.id), [added.id])
    }

    @MainActor
    func testAddRejectsWhenNoUsableTerms() {
        let port = InMemoryFilterStoring()
        let store = SavedFilterStore(port: port)

        XCTAssertNil(store.add(
            name: "Empty", terms: [FilterTerm(kind: .keyword, value: "   ")], combinator: .or
        ))
        XCTAssertTrue(store.filters.isEmpty)
        XCTAssertTrue(port.saved.isEmpty)
    }

    @MainActor
    func testAddUsesJoinedSubqueriesAsNameWhenBlank() throws {
        let port = InMemoryFilterStoring()
        let store = SavedFilterStore(port: port)

        let added = try XCTUnwrap(store.add(
            name: "  ",
            terms: [FilterTerm(kind: .user, value: "alice.bsky.social"),
                    FilterTerm(kind: .user, value: "bob.bsky.social")],
            combinator: .or
        ))
        XCTAssertEqual(added.name, "from:alice.bsky.social | from:bob.bsky.social")
    }

    @MainActor
    func testUpdateReplacesByIdAndPersists() throws {
        let original = SavedFilter(name: "Swift", terms: [FilterTerm(kind: .hashtag, value: "swift")], combinator: .and)
        let port = InMemoryFilterStoring(initial: [original])
        let store = SavedFilterStore(port: port)

        var edited = original
        edited.name = "Swift Lang"
        edited.combinator = .or
        store.update(edited)

        XCTAssertEqual(store.filters.first?.name, "Swift Lang")
        XCTAssertEqual(store.filters.first?.combinator, .or)
        XCTAssertEqual(port.saved.last?.first?.name, "Swift Lang")
    }

    @MainActor
    func testRemoveDeletesByIdAndPersists() {
        let a = SavedFilter(name: "A", terms: [FilterTerm(kind: .keyword, value: "a")], combinator: .and)
        let b = SavedFilter(name: "B", terms: [FilterTerm(kind: .keyword, value: "b")], combinator: .and)
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
