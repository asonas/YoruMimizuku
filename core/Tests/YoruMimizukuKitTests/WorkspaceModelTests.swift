import XCTest
@testable import YoruMimizukuKit

@MainActor
final class WorkspaceModelTests: XCTestCase {
    private final class StubThreadLoader: ThreadLoading, @unchecked Sendable {
        func loadThread(uri: String) async throws -> PostDisplay {
            PostDisplay(id: uri, authorDisplayName: "x", authorHandle: "x", body: "x", createdAt: Date())
        }
    }

    private final class FakePersistence: ConversationPersisting, @unchecked Sendable {
        var state: ConversationState
        private(set) var saveCount = 0
        init(state: ConversationState = ConversationState()) { self.state = state }
        func load() -> ConversationState { state }
        func save(_ state: ConversationState) { self.state = state; saveCount += 1 }
    }

    private func makeModel(persistence: ConversationPersisting) -> WorkspaceModel {
        WorkspaceModel(persistence: persistence) { uri in
            ThreadViewModel(loader: StubThreadLoader(), uri: uri)
        }
    }

    private func post(id: String, name: String = "Alice", handle: String = "alice.bsky.social") -> PostDisplay {
        PostDisplay(id: id, authorDisplayName: name, authorHandle: handle, body: "body", createdAt: Date())
    }

    func testRestoresSavedConversationsOnInit() {
        let persistence = FakePersistence(state: ConversationState(
            conversations: [
                SavedConversation(anchorID: "at://a", title: "Alice", handle: "@alice", subtitle: "hi"),
                SavedConversation(anchorID: "at://b", title: "Bob", handle: "@bob", subtitle: "yo")
            ],
            selectedAnchorID: "at://b"
        ))

        let model = makeModel(persistence: persistence)

        XCTAssertEqual(model.conversations.map(\.anchorID), ["at://a", "at://b"])
        XCTAssertEqual(model.conversations.map(\.title), ["Alice", "Bob"])
        guard case let .conversation(id) = model.selection else { return XCTFail("expected conversation selection") }
        XCTAssertEqual(model.conversation(id: id)?.anchorID, "at://b")
    }

    func testRestoreWithNoSelectionFallsBackToHome() {
        let persistence = FakePersistence(state: ConversationState(
            conversations: [SavedConversation(anchorID: "at://a", title: "Alice", handle: "@alice", subtitle: "hi")],
            selectedAnchorID: nil
        ))

        let model = makeModel(persistence: persistence)

        XCTAssertEqual(model.selection, .home)
    }

    func testOpenConversationPersistsTabAndSelection() {
        let persistence = FakePersistence()
        let model = makeModel(persistence: persistence)

        model.openConversation(post(id: "at://a"))

        XCTAssertEqual(persistence.state.conversations.map(\.anchorID), ["at://a"])
        XCTAssertEqual(persistence.state.selectedAnchorID, "at://a")
    }

    func testCloseConversationPersistsRemoval() {
        let persistence = FakePersistence()
        let model = makeModel(persistence: persistence)
        model.openConversation(post(id: "at://a"))
        let id = model.conversations[0].id

        model.closeConversation(id)

        XCTAssertTrue(persistence.state.conversations.isEmpty)
        XCTAssertNil(persistence.state.selectedAnchorID)
    }

    func testRestoreThenReopenRoundTrips() {
        // Simulate a relaunch: persist with one model, restore with a fresh one
        // backed by the same store.
        let persistence = FakePersistence()
        let first = makeModel(persistence: persistence)
        first.openConversation(post(id: "at://a", name: "Alice"))

        let restored = makeModel(persistence: persistence)

        XCTAssertEqual(restored.conversations.map(\.anchorID), ["at://a"])
        XCTAssertEqual(restored.conversations.first?.title, "Alice")
    }
}
