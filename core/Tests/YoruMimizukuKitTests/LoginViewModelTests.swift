import XCTest
@testable import YoruMimizukuKit

@MainActor
final class LoginViewModelTests: XCTestCase {
    private final class StubPerformer: LoginPerforming, @unchecked Sendable {
        var result: Result<String, Error>
        private(set) var receivedHandle: String?
        init(result: Result<String, Error>) { self.result = result }
        func login(handle: String) async throws -> String {
            receivedHandle = handle
            return try result.get()
        }
    }

    private struct StubError: Error {}

    func testInitialStateIsIdle() {
        let vm = LoginViewModel(performer: StubPerformer(result: .success("did:plc:a")))
        XCTAssertEqual(vm.state, .idle)
    }

    func testCannotSubmitWhenHandleBlank() {
        let vm = LoginViewModel(performer: StubPerformer(result: .success("did:plc:a")))
        vm.handle = "   "
        XCTAssertFalse(vm.canSubmit)
        vm.handle = "alice.bsky.social"
        XCTAssertTrue(vm.canSubmit)
    }

    func testSuccessfulSubmitReachesAuthenticated() async {
        let performer = StubPerformer(result: .success("did:plc:a"))
        let vm = LoginViewModel(performer: performer)
        vm.handle = "  alice.bsky.social  "
        await vm.submit()
        XCTAssertEqual(vm.state, .authenticated(did: "did:plc:a"))
        // Handle is trimmed before being passed to the performer.
        XCTAssertEqual(performer.receivedHandle, "alice.bsky.social")
    }

    func testFailedSubmitReachesFailedState() async {
        let vm = LoginViewModel(performer: StubPerformer(result: .failure(StubError())))
        vm.handle = "alice.bsky.social"
        await vm.submit()
        guard case .failed = vm.state else {
            return XCTFail("expected failed state, got \(vm.state)")
        }
    }

    func testResetClearsHandleAndState() async {
        let vm = LoginViewModel(performer: StubPerformer(result: .success("did:plc:a")))
        vm.handle = "alice.bsky.social"
        await vm.submit()
        XCTAssertEqual(vm.state, .authenticated(did: "did:plc:a"))

        vm.reset()

        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.handle, "")
    }

    func testSubmitWithBlankHandleDoesNothing() async {
        let performer = StubPerformer(result: .success("did:plc:a"))
        let vm = LoginViewModel(performer: performer)
        vm.handle = "   "
        await vm.submit()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertNil(performer.receivedHandle)
    }
}
