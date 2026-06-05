import XCTest
@testable import YoruMimizukuKit

@MainActor
final class ThreadViewModelTests: XCTestCase {
    private final class StubLoader: ThreadLoading, @unchecked Sendable {
        var result: Result<PostDisplay, Error>
        private(set) var requestedURIs: [String] = []
        init(result: Result<PostDisplay, Error>) { self.result = result }
        func loadThread(uri: String) async throws -> PostDisplay {
            requestedURIs.append(uri)
            return try result.get()
        }
    }

    private struct StubError: Error {}

    private func sample(id: String, parent: PostDisplay? = nil) -> PostDisplay {
        PostDisplay(
            id: id, authorDisplayName: "Bob", authorHandle: "bob.bsky.social",
            body: "reply", createdAt: Date(timeIntervalSince1970: 1_780_574_400),
            replyParent: parent.map(ReplyParent.init)
        )
    }

    func testInitialStateIsIdle() {
        let vm = ThreadViewModel(loader: StubLoader(result: .success(sample(id: "x"))), uri: "x")
        XCTAssertEqual(vm.state, .idle)
    }

    func testSuccessfulLoadReachesLoadedAndRequestsURI() async {
        let parent = sample(id: "root")
        let focus = sample(id: "reply", parent: parent)
        let loader = StubLoader(result: .success(focus))
        let vm = ThreadViewModel(loader: loader, uri: "reply")

        await vm.load()

        XCTAssertEqual(vm.state, .loaded(focus))
        XCTAssertEqual(loader.requestedURIs, ["reply"])
    }

    func testFailedLoadReachesFailed() async {
        let vm = ThreadViewModel(loader: StubLoader(result: .failure(StubError())), uri: "x")
        await vm.load()
        guard case .failed = vm.state else {
            return XCTFail("expected failed state, got \(vm.state)")
        }
    }
}
