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

    func testReplyParentPostIsStoredAndDraftUsesItsURI() async {
        let submitter = FakeSubmitter()
        let parent = PostDisplay(
            id: "at://did:plc:parent/app.bsky.feed.post/abc",
            authorDisplayName: "Alice",
            authorHandle: "alice.bsky.social",
            body: "This is the post being replied to",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let vm = ComposerViewModel(submitter: submitter, replyParent: parent)
        vm.text = "reply"

        XCTAssertEqual(vm.replyParent?.id, parent.id)

        await vm.submit()

        XCTAssertEqual(submitter.received?.replyParentURI, parent.id)
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

    func testSubmitTrimsTrailingBlankLines() async {
        let submitter = FakeSubmitter()
        let vm = ComposerViewModel(submitter: submitter)
        vm.text = "hello\n\n"

        await vm.submit()

        XCTAssertEqual(submitter.received?.text, "hello")
    }

    func testSubmitPreservesInteriorBlankLines() async {
        let submitter = FakeSubmitter()
        let vm = ComposerViewModel(submitter: submitter)
        vm.text = "line1\n\nline2\n \n"

        await vm.submit()

        XCTAssertEqual(submitter.received?.text, "line1\n\nline2")
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

    // 13. A video and images are mutually exclusive.
    func testVideoAndImagesAreMutuallyExclusive() {
        let vm = ComposerViewModel(submitter: FakeSubmitter())
        XCTAssertTrue(vm.canAddImage)
        XCTAssertTrue(vm.canAddVideo)

        vm.video = ComposeVideo(data: Data([0x1]), mimeType: "video/mp4")
        XCTAssertFalse(vm.canAddImage) // video present blocks images

        vm.video = nil
        vm.images = [ComposeImage(data: Data([0x1]), mimeType: "image/jpeg")]
        XCTAssertFalse(vm.canAddVideo) // images present block a video
    }

    // 14. A video alone makes the draft submittable.
    func testVideoAloneIsSubmittable() {
        let vm = ComposerViewModel(submitter: FakeSubmitter())
        XCTAssertFalse(vm.canSubmit)
        vm.video = ComposeVideo(data: Data([0x1]), mimeType: "video/mp4")
        XCTAssertTrue(vm.canSubmit)
    }

    // 15. submit() forwards the video on the draft.
    func testSubmitForwardsVideo() async {
        let submitter = FakeSubmitter()
        let vm = ComposerViewModel(submitter: submitter)
        vm.video = ComposeVideo(data: Data([0xAA]), mimeType: "video/mp4", alt: "clip",
                                filename: "clip.mp4", width: 720, height: 1280)

        await vm.submit()

        XCTAssertEqual(submitter.received?.video?.alt, "clip")
        XCTAssertEqual(submitter.received?.video?.mimeType, "video/mp4")
        XCTAssertEqual(submitter.received?.video?.width, 720)
        XCTAssertEqual(vm.submitPhase, .idle)
    }
}
