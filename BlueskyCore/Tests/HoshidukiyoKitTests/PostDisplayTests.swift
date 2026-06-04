import XCTest
@testable import HoshidukiyoKit

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

    func test_samples_returnNonEmptyDeterministicData() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = PostDisplay.samples(now: now)

        XCTAssertGreaterThanOrEqual(samples.count, 3)
        XCTAssertEqual(Set(samples.map(\.id)).count, samples.count)
        XCTAssertTrue(samples.allSatisfy { $0.createdAt <= now })
        XCTAssertEqual(samples, samples.sorted { $0.createdAt > $1.createdAt })
    }
}
