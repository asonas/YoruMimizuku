import XCTest
@testable import YoruMimizukuKit

final class FeedThreadingTests: XCTestCase {
    /// Build a post; `author` sets both display name and handle (defaults keep
    /// existing single-author tests unchanged); `parent` links it as reply parent.
    private func post(
        _ id: String,
        createdAt: TimeInterval,
        author: String = "a.example",
        parent: PostDisplay? = nil
    ) -> PostDisplay {
        PostDisplay(
            id: id,
            authorDisplayName: author,
            authorHandle: author,
            body: "body \(id)",
            createdAt: Date(timeIntervalSince1970: createdAt),
            replyParent: parent.map(ReplyParent.init)
        )
    }

    func testPlainPostsKeepOrderWithoutConnections() {
        let posts = [post("b", createdAt: 200), post("a", createdAt: 100)]

        let items = FeedThreading.arrange(posts)

        XCTAssertEqual(items.map(\.post.id), ["b", "a"])
        XCTAssertEqual(items.map(\.connectsToPrevious), [false, false])
        XCTAssertEqual(items.map(\.connectsToNext), [false, false])
    }

    func testSelfThreadIsGroupedOldestFirst() {
        let c1 = post("c1", createdAt: 100)
        let c2 = post("c2", createdAt: 200, parent: c1)
        let c3 = post("c3", createdAt: 300, parent: c2)

        let items = FeedThreading.arrange([c3, c2, c1])

        XCTAssertEqual(items.map(\.post.id), ["c1", "c2", "c3"])
        XCTAssertEqual(items.map(\.connectsToPrevious), [false, true, true])
        XCTAssertEqual(items.map(\.connectsToNext), [true, true, false])
    }

    func testGroupIsEmittedAtItsNewestMemberPosition() {
        let c1 = post("c1", createdAt: 100)
        let c2 = post("c2", createdAt: 200, parent: c1)
        let c3 = post("c3", createdAt: 300, parent: c2)
        let x = post("x", createdAt: 400)
        let y = post("y", createdAt: 150)

        let items = FeedThreading.arrange([x, c3, c2, y, c1])

        XCTAssertEqual(items.map(\.post.id), ["x", "c1", "c2", "c3", "y"])
    }

    func testReplyWhoseParentIsNotInThePageStaysSingle() {
        let absentParent = post("absent", createdAt: 50)
        let reply = post("r", createdAt: 100, parent: absentParent)
        let other = post("o", createdAt: 200)

        let items = FeedThreading.arrange([other, reply])

        XCTAssertEqual(items.map(\.post.id), ["o", "r"])
        XCTAssertEqual(items.map(\.connectsToPrevious), [false, false])
        XCTAssertEqual(items.map(\.connectsToNext), [false, false])
    }

    func testParentAndReplyPairConnects() {
        let parent = post("p", createdAt: 100)
        let reply = post("r", createdAt: 200, parent: parent)

        let items = FeedThreading.arrange([reply, parent])

        XCTAssertEqual(items.map(\.post.id), ["p", "r"])
        XCTAssertEqual(items[0].connectsToNext, true)
        XCTAssertEqual(items[1].connectsToPrevious, true)
    }

    func testDuplicatePostIDsAreEmittedOnce() {
        let a = post("a", createdAt: 100)
        let duplicate = post("a", createdAt: 100)
        let b = post("b", createdAt: 200)

        let items = FeedThreading.arrange([b, a, duplicate])

        XCTAssertEqual(items.map(\.post.id), ["b", "a"])
    }

    func testParentCycleDoesNotHang() {
        // Defensive: two posts that (impossibly) name each other as parents must
        // not loop forever; both still render.
        let seedA = post("a", createdAt: 100)
        let seedB = post("b", createdAt: 200, parent: seedA)
        let a = post("a", createdAt: 100, parent: seedB)

        let items = FeedThreading.arrange([seedB, a])

        XCTAssertEqual(Set(items.map(\.post.id)), ["a", "b"])
        XCTAssertEqual(items.count, 2)
    }

    func testMultiAuthorRepliesDoNotMergeIntoOneBlock() {
        // root by A; two replies to root by different authors B and C. The old
        // behavior merged all three into one chronological block; now each reply
        // is an independent row (parent author != reply author).
        let root = post("root", createdAt: 100, author: "a.example")
        let b = post("b", createdAt: 200, author: "b.example", parent: root)
        let c = post("c", createdAt: 300, author: "c.example", parent: root)

        // Realistic newest-first page order.
        let items = FeedThreading.arrange([c, b, root])

        XCTAssertEqual(items.map(\.post.id), ["c", "b", "root"])
        XCTAssertEqual(items.map(\.connectsToPrevious), [false, false, false])
        XCTAssertEqual(items.map(\.connectsToNext), [false, false, false])
    }
}
