import XCTest
@testable import YoruMimizukuKit

@MainActor
final class ComposerViewModelTests: XCTestCase {
    private final class FakeSubmitter: PostSubmitting, @unchecked Sendable {
        var received: PostDraft?
        var result: Result<PostResult, Error> = .success(PostResult(uri: "at://x", cid: "c"))
        func submit(_ draft: PostDraft) async throws -> PostResult {
            received = draft
            return try result.get()
        }
    }

    func testCanSubmitRequiresContentWithinLimit() {
        let vm = ComposerViewModel(submitter: FakeSubmitter())
        XCTAssertFalse(vm.canSubmit) // empty
        vm.text = "hello"
        XCTAssertTrue(vm.canSubmit)
        vm.text = String(repeating: "a", count: 301)
        XCTAssertFalse(vm.canSubmit) // over 300 graphemes
        XCTAssertEqual(vm.remaining, -1)
    }

    func testGraphemeCountCountsClustersNotUTF16() {
        let vm = ComposerViewModel(submitter: FakeSubmitter())
        vm.text = "👨‍👩‍👧‍👦" // one grapheme cluster
        XCTAssertEqual(vm.graphemeCount, 1)
        XCTAssertTrue(vm.canSubmit)
    }

    func testSubmitForwardsDraftAndReportsSuccess() async {
        let submitter = FakeSubmitter()
        let vm = ComposerViewModel(submitter: submitter, replyParentURI: "at://parent")
        vm.text = "hi"
        var posted = false
        vm.onPosted = { posted = true }

        await vm.submit()

        XCTAssertEqual(submitter.received?.text, "hi")
        XCTAssertEqual(submitter.received?.replyParentURI, "at://parent")
        XCTAssertTrue(posted)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isSubmitting)
    }

    func testQuotePostIsSubmittableWithEmptyTextAndForwardsQuote() async {
        let submitter = FakeSubmitter()
        let quoted = PostDisplay(
            id: "at://did:plc:a/app.bsky.feed.post/x", cid: "bafyquote",
            authorDisplayName: "Alice", authorHandle: "alice.bsky.social",
            body: "original", createdAt: Date()
        )
        let vm = ComposerViewModel(submitter: submitter, quotedPost: quoted)

        XCTAssertTrue(vm.canSubmit) // quoting alone, no text, is allowed

        await vm.submit()

        XCTAssertEqual(submitter.received?.quote?.uri, "at://did:plc:a/app.bsky.feed.post/x")
        XCTAssertEqual(submitter.received?.quote?.cid, "bafyquote")
    }

    func testSubmitSetsErrorMessageOnFailure() async {
        let submitter = FakeSubmitter()
        submitter.result = .failure(NSError(domain: "x", code: 1))
        let vm = ComposerViewModel(submitter: submitter)
        vm.text = "hi"

        await vm.submit()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isSubmitting)
    }
}
