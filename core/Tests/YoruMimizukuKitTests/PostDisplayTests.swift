import XCTest
@testable import YoruMimizukuKit

final class PostDisplayTests: XCTestCase {
    func test_initStoresAllFields() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let post = PostDisplay(
            id: "p1",
            authorDisplayName: "あそなす",
            authorHandle: "asonas.bsky.social",
            body: "hello",
            createdAt: date,
            contextLabel: "Reposted by you",
            replyCount: 1,
            repostCount: 2,
            likeCount: 3
        )

        XCTAssertEqual(post.id, "p1")
        XCTAssertEqual(post.authorDisplayName, "あそなす")
        XCTAssertEqual(post.authorHandle, "asonas.bsky.social")
        XCTAssertEqual(post.body, "hello")
        XCTAssertEqual(post.createdAt, date)
        XCTAssertEqual(post.contextLabel, "Reposted by you")
        XCTAssertEqual(post.replyCount, 1)
        XCTAssertEqual(post.repostCount, 2)
        XCTAssertEqual(post.likeCount, 3)
    }

    func test_applyOptimisticLike_setsLikedAndIncrementsCount() {
        var post = PostDisplay(id: "p", authorDisplayName: "a", authorHandle: "a", body: "b", createdAt: Date(), likeCount: 3)

        post.applyOptimisticLike()

        XCTAssertTrue(post.isLiked)
        XCTAssertNotNil(post.viewerLikeURI)
        XCTAssertEqual(post.likeCount, 4)
    }

    func test_applyOptimisticLike_isNoOpWhenAlreadyLiked() {
        var post = PostDisplay(id: "p", authorDisplayName: "a", authorHandle: "a", body: "b", createdAt: Date(),
                               likeCount: 4, viewerLikeURI: "at://did/app.bsky.feed.like/x")

        post.applyOptimisticLike()

        XCTAssertEqual(post.likeCount, 4)
        XCTAssertEqual(post.viewerLikeURI, "at://did/app.bsky.feed.like/x")
    }

    func test_applyOptimisticUnlike_clearsAndDecrementsCount() {
        var post = PostDisplay(id: "p", authorDisplayName: "a", authorHandle: "a", body: "b", createdAt: Date(),
                               likeCount: 5, viewerLikeURI: "at://did/app.bsky.feed.like/x")

        post.applyOptimisticUnlike()

        XCTAssertFalse(post.isLiked)
        XCTAssertNil(post.viewerLikeURI)
        XCTAssertEqual(post.likeCount, 4)
    }

    func test_applyOptimisticUnlike_doesNotGoBelowZero() {
        var post = PostDisplay(id: "p", authorDisplayName: "a", authorHandle: "a", body: "b", createdAt: Date(),
                               likeCount: 0, viewerLikeURI: "at://did/app.bsky.feed.like/x")

        post.applyOptimisticUnlike()

        XCTAssertEqual(post.likeCount, 0)
    }

    func test_applyOptimisticRepost_andUnrepost() {
        var post = PostDisplay(id: "p", authorDisplayName: "a", authorHandle: "a", body: "b", createdAt: Date(), repostCount: 1)

        post.applyOptimisticRepost()
        XCTAssertTrue(post.isReposted)
        XCTAssertEqual(post.repostCount, 2)

        post.applyOptimisticUnrepost()
        XCTAssertFalse(post.isReposted)
        XCTAssertEqual(post.repostCount, 1)
    }

    func test_samples_returnNonEmptyDeterministicData() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = PostDisplay.samples(now: now)

        XCTAssertGreaterThanOrEqual(samples.count, 3)
        XCTAssertEqual(Set(samples.map(\.id)).count, samples.count)
        XCTAssertTrue(samples.allSatisfy { $0.createdAt <= now })
        XCTAssertEqual(samples, samples.sorted { $0.createdAt > $1.createdAt })
    }
}
