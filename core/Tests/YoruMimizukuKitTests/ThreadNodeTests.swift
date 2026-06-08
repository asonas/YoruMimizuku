import XCTest
@testable import YoruMimizukuKit
import BlueskyCore

final class ThreadNodeTests: XCTestCase {
    // Build a hydrated PostView with the given uri/handle and a child reply list.
    private func post(_ uri: String, handle: String) -> PostView {
        PostView(
            uri: uri, cid: "cid-\(uri)",
            author: ProfileViewBasic(did: "did:\(handle)", handle: handle, displayName: nil, avatar: nil),
            record: PostRecord(text: "t-\(uri)", createdAt: "2026-06-04T12:00:00.000Z"),
            replyCount: 0, repostCount: 0, likeCount: 0,
            indexedAt: "2026-06-04T12:00:01.000Z"
        )
    }

    private func node(_ uri: String, handle: String, replies: [ThreadViewPost] = []) -> ThreadViewPost {
        ThreadViewPost(post: post(uri, handle: handle), parent: nil, replies: replies)
    }

    func testEmptyRepliesReturnsEmptyTree() {
        let anchor = node("anchor", handle: "a")  // no replies
        XCTAssertTrue(ThreadNode.childTree(of: anchor, maxDepth: 3).isEmpty)
    }

    func testMultipleChildrenPreserveServerOrder() {
        let anchor = node("anchor", handle: "a", replies: [
            node("b", handle: "b"),
            node("c", handle: "c")
        ])

        let tree = ThreadNode.childTree(of: anchor, maxDepth: 3)

        XCTAssertEqual(tree.map(\.id), ["b", "c"])
        XCTAssertEqual(tree.map(\.depth), [0, 0])
    }

    func testNestedChildrenIncrementDepth() {
        let anchor = node("anchor", handle: "a", replies: [
            node("b", handle: "b", replies: [
                node("c", handle: "c")
            ])
        ])

        let tree = ThreadNode.childTree(of: anchor, maxDepth: 3)

        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree[0].depth, 0)
        XCTAssertEqual(tree[0].replies.count, 1)
        XCTAssertEqual(tree[0].replies[0].id, "c")
        XCTAssertEqual(tree[0].replies[0].depth, 1)
    }

    func testMaxDepthTruncationLeavesRepliesEmpty() {
        // anchor -> b(0) -> c(1) -> d(2); with maxDepth 1, c is at the cap so its
        // own children (d) are not built.
        let anchor = node("anchor", handle: "a", replies: [
            node("b", handle: "b", replies: [
                node("c", handle: "c", replies: [
                    node("d", handle: "d")
                ])
            ])
        ])

        let tree = ThreadNode.childTree(of: anchor, maxDepth: 1)

        XCTAssertEqual(tree[0].id, "b")
        XCTAssertEqual(tree[0].replies[0].id, "c")
        XCTAssertEqual(tree[0].replies[0].depth, 1)
        XCTAssertTrue(tree[0].replies[0].replies.isEmpty, "node at the depth cap must not build deeper children")
    }
}
