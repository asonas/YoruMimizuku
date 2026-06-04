import XCTest
import BlueskyCore
@testable import HoshidukiyoKit

final class PostDisplayMappingTests: XCTestCase {
    private func post(
        uri: String = "at://did:plc:alice/app.bsky.feed.post/aaa",
        handle: String = "alice.bsky.social",
        displayName: String? = "Alice",
        avatar: String? = nil,
        text: String = "hello",
        createdAt: String = "2026-06-04T12:00:00.000Z",
        replyCount: Int? = nil,
        repostCount: Int? = nil,
        likeCount: Int? = nil
    ) -> PostView {
        PostView(
            uri: uri,
            cid: "cid",
            author: ProfileViewBasic(did: "did:plc:alice", handle: handle, displayName: displayName, avatar: avatar),
            record: PostRecord(text: text, createdAt: createdAt),
            replyCount: replyCount,
            repostCount: repostCount,
            likeCount: likeCount,
            indexedAt: "2026-06-04T12:00:01.000Z"
        )
    }

    func testMapsPlainPost() {
        let item = FeedViewPost(post: post(text: "hi there", replyCount: 1, repostCount: 2, likeCount: 3))

        let display = PostDisplay(item)

        XCTAssertEqual(display.id, "at://did:plc:alice/app.bsky.feed.post/aaa")
        XCTAssertEqual(display.authorDisplayName, "Alice")
        XCTAssertEqual(display.authorHandle, "alice.bsky.social")
        XCTAssertEqual(display.body, "hi there")
        XCTAssertNil(display.contextLabel)
        XCTAssertEqual(display.replyCount, 1)
        XCTAssertEqual(display.repostCount, 2)
        XCTAssertEqual(display.likeCount, 3)
    }

    func testFallsBackToHandleAndZeroCountsWhenAbsent() {
        let item = FeedViewPost(post: post(displayName: nil))

        let display = PostDisplay(item)

        XCTAssertEqual(display.authorDisplayName, "alice.bsky.social")
        XCTAssertNil(display.avatarURL)
        XCTAssertEqual(display.replyCount, 0)
        XCTAssertEqual(display.repostCount, 0)
        XCTAssertEqual(display.likeCount, 0)
    }

    func testMapsAvatarURL() {
        let item = FeedViewPost(post: post(avatar: "https://cdn.example/alice.jpg"))

        let display = PostDisplay(item)

        XCTAssertEqual(display.avatarURL, URL(string: "https://cdn.example/alice.jpg"))
    }

    func testMapsImageEmbed() {
        let embed = PostEmbed(images: [
            EmbedImage(thumb: "https://cdn.example/t1.jpg", fullsize: "https://cdn.example/f1.jpg", alt: "cat"),
            EmbedImage(thumb: "https://cdn.example/t2.jpg", fullsize: "https://cdn.example/f2.jpg", alt: "")
        ])
        let postView = PostView(
            uri: "at://did:plc:alice/app.bsky.feed.post/aaa",
            cid: "cid",
            author: ProfileViewBasic(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatar: nil),
            record: PostRecord(text: "look", createdAt: "2026-06-04T12:00:00.000Z"),
            replyCount: nil, repostCount: nil, likeCount: nil,
            indexedAt: "2026-06-04T12:00:01.000Z",
            embed: embed
        )

        let display = PostDisplay(FeedViewPost(post: postView))

        XCTAssertEqual(display.images.count, 2)
        XCTAssertEqual(display.images[0].thumbURL, URL(string: "https://cdn.example/t1.jpg"))
        XCTAssertEqual(display.images[0].fullsizeURL, URL(string: "https://cdn.example/f1.jpg"))
        XCTAssertEqual(display.images[0].alt, "cat")
    }

    func testNoEmbedMapsToNoImages() {
        let display = PostDisplay(FeedViewPost(post: post()))
        XCTAssertEqual(display.images, [])
    }

    func testMapsReplyParent() {
        let parent = post(
            uri: "at://did:plc:bob/app.bsky.feed.post/parent",
            handle: "bob.bsky.social",
            displayName: "Bob",
            text: "original question"
        )
        let item = FeedViewPost(post: post(text: "agreed!"), reply: ReplyRef(parent: parent))

        let display = PostDisplay(item)

        let replyParent = try? XCTUnwrap(display.replyParent)
        XCTAssertEqual(replyParent?.post.authorHandle, "bob.bsky.social")
        XCTAssertEqual(replyParent?.post.body, "original question")
        XCTAssertEqual(replyParent?.post.id, "at://did:plc:bob/app.bsky.feed.post/parent")
    }

    func testNoReplyMapsToNilReplyParent() {
        let display = PostDisplay(FeedViewPost(post: post()))
        XCTAssertNil(display.replyParent)
    }

    func testRepostReasonBecomesContextLabel() {
        let reason = ReasonRepost(
            by: ProfileViewBasic(did: "did:plc:bob", handle: "bob.bsky.social", displayName: "Bob", avatar: nil),
            indexedAt: "2026-06-04T11:45:00.000Z"
        )
        let item = FeedViewPost(post: post(), reason: reason)

        let display = PostDisplay(item)

        XCTAssertEqual(display.contextLabel, "Reposted by Bob")
    }

    func testParsesFractionalAndWholeSecondTimestamps() {
        let fractional = PostDisplay(FeedViewPost(post: post(createdAt: "2026-06-04T12:00:00.000Z")))
        let whole = PostDisplay(FeedViewPost(post: post(createdAt: "2026-06-04T12:00:00Z")))

        XCTAssertEqual(fractional.createdAt, whole.createdAt)
        // Parsed, not the epoch-0 fallback used for unparseable timestamps.
        XCTAssertGreaterThan(fractional.createdAt.timeIntervalSince1970, 1_700_000_000)
    }
}
