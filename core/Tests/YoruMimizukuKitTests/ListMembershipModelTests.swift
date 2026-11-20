import XCTest
import BlueskyCore
@testable import YoruMimizukuKit

// Test methods are `async` so swift-corelibs-xctest on Windows runs these
// `@MainActor` tests through its async invoker (see WorkspaceModelTests).
@MainActor
final class ListMembershipModelTests: XCTestCase {
    /// An in-memory stand-in for the server: which actors are on which list.
    private actor FakeServer: ListMembershipEditing {
        let lists: [(uri: String, name: String)]
        private var items: [String: (actor: String, list: String)] = [:]
        private var nextID = 0
        private(set) var writes: [String] = []

        init(lists: [(uri: String, name: String)]) { self.lists = lists }

        func putOnList(_ actor: String, _ list: String) -> String {
            nextID += 1
            let uri = "at://did:plc:me/app.bsky.graph.listitem/\(nextID)"
            items[uri] = (actor, list)
            return uri
        }

        func lists(withMembershipOf actorDID: String) async throws -> [CuratedListMembership] {
            lists.map { list in
                let item = items.first { $0.value.actor == actorDID && $0.value.list == list.uri }?.key
                return CuratedListMembership(listURI: list.uri, name: list.name, itemURI: item)
            }
        }

        func add(actorDID: String, toList listURI: String) async throws -> String {
            writes.append("add \(actorDID) \(listURI)")
            return putOnList(actorDID, listURI)
        }

        func remove(itemURI: String) async throws {
            writes.append("remove \(itemURI)")
            items[itemURI] = nil
        }
    }

    private let close = (uri: "at://did:plc:me/app.bsky.graph.list/close", name: "近しい人")
    private let swift = (uri: "at://did:plc:me/app.bsky.graph.list/swift", name: "Swift")

    func testRefreshListsTheOwnListsAndWhetherTheActorIsOnEach() async throws {
        let server = FakeServer(lists: [close, swift])
        _ = await server.putOnList("did:plc:alice", close.uri)
        let model = ListMembershipModel(editor: server)

        await model.refresh(actorDID: "did:plc:alice")

        XCTAssertEqual(model.lists.map(\.name), ["近しい人", "Swift"])
        XCTAssertEqual(model.isMember("did:plc:alice", of: close.uri), true)
        XCTAssertEqual(model.isMember("did:plc:alice", of: swift.uri), false)
        XCTAssertNil(model.isMember("did:plc:bob", of: close.uri))
    }

    private struct FailingEditor: ListMembershipEditing {
        struct Failure: Error {}
        func lists(withMembershipOf actorDID: String) async throws -> [CuratedListMembership] { throw Failure() }
        func add(actorDID: String, toList listURI: String) async throws -> String { throw Failure() }
        func remove(itemURI: String) async throws { throw Failure() }
    }

    /// The menu must tell "you have no lists" apart from "the lists did not load".
    func testListsStateTellsNoListsApartFromAFailedLoad() async throws {
        let empty = ListMembershipModel(editor: FakeServer(lists: []))
        let failing = ListMembershipModel(editor: FailingEditor())
        XCTAssertEqual(empty.listsState, .notLoaded)

        await empty.refresh(actorDID: "did:plc:alice")
        await failing.refresh(actorDID: "did:plc:alice")

        XCTAssertEqual(empty.listsState, .loaded)
        XCTAssertEqual(failing.listsState, .failed)
    }

    func testAddingPutsTheActorOnTheList() async throws {
        let server = FakeServer(lists: [close])
        let model = ListMembershipModel(editor: server)

        let wrote = try await model.setMembership("did:plc:alice", of: close.uri, to: true)

        XCTAssertTrue(wrote)
        XCTAssertEqual(model.isMember("did:plc:alice", of: close.uri), true)
        let writes = await server.writes
        XCTAssertEqual(writes, ["add did:plc:alice \(close.uri)"])
    }

    /// The cache can be stale (another client added the actor), and the PDS
    /// accepts a second identical list item, so a write re-reads first.
    func testAddingAnActorAlreadyOnTheListWritesNothing() async throws {
        let server = FakeServer(lists: [close])
        let model = ListMembershipModel(editor: server)
        await model.refresh(actorDID: "did:plc:alice")
        _ = await server.putOnList("did:plc:alice", close.uri)

        let wrote = try await model.setMembership("did:plc:alice", of: close.uri, to: true)

        XCTAssertFalse(wrote)
        let writes = await server.writes
        XCTAssertEqual(writes, [])
        XCTAssertEqual(model.isMember("did:plc:alice", of: close.uri), true)
    }

    func testRemovingTakesTheActorOffTheList() async throws {
        let server = FakeServer(lists: [close])
        let item = await server.putOnList("did:plc:alice", close.uri)
        let model = ListMembershipModel(editor: server)

        try await model.setMembership("did:plc:alice", of: close.uri, to: false)

        XCTAssertEqual(model.isMember("did:plc:alice", of: close.uri), false)
        let writes = await server.writes
        XCTAssertEqual(writes, ["remove \(item)"])
    }
}
