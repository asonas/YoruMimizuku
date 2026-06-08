import XCTest
@testable import YoruMimizukuKit

@MainActor
final class ProfileHeaderViewModelTests: XCTestCase {
    private final class StubLoader: AuthorProfileLoading, @unchecked Sendable {
        let result: Result<AuthorProfile, Error>
        init(_ result: Result<AuthorProfile, Error>) { self.result = result }
        func loadProfile(actor: String) async throws -> AuthorProfile {
            try result.get()
        }
    }

    private struct LoadError: Error {}

    private func profile(did: String = "did:plc:alice") -> AuthorProfile {
        AuthorProfile(
            did: did, handle: "alice.bsky.social", displayName: "Alice",
            avatarURL: URL(string: "https://cdn.example/alice.jpg"), bio: "hello"
        )
    }

    func testLoadSuccessSetsProfile() async {
        let loaded = profile()
        let vm = ProfileHeaderViewModel(loader: StubLoader(.success(loaded)), actor: "did:plc:alice")

        await vm.load()

        XCTAssertEqual(vm.profile, loaded)
        XCTAssertFalse(vm.failed)
    }

    func testLoadFailureKeepsInitialAndMarksFailed() async {
        let initial = profile()
        let vm = ProfileHeaderViewModel(
            loader: StubLoader(.failure(LoadError())), actor: "did:plc:alice", initial: initial
        )

        await vm.load()

        XCTAssertEqual(vm.profile, initial)
        XCTAssertTrue(vm.failed)
    }
}
