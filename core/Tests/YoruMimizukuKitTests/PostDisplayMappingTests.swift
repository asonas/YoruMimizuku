import XCTest
import BlueskyCore
@testable import YoruMimizukuKit

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
        likeCount: Int? = nil,
        labels: [Label] = []
    ) -> PostView {
        PostView(
            uri: uri,
            cid: "cid",
            author: ProfileViewBasic(did: "did:plc:alice", handle: handle, displayName: displayName, avatar: avatar),
            record: PostRecord(text: text, createdAt: createdAt),
            replyCount: replyCount,
            repostCount: repostCount,
            likeCount: likeCount,
            indexedAt: "2026-06-04T12:00:01.000Z",
            labels: labels
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

    func testMapsAdultSelfLabelToMediaWarning() {
        let display = PostDisplay(FeedViewPost(post: post(labels: [Label(val: "porn", src: "did:plc:alice")])))

        XCTAssertEqual(display.mediaWarning, .adult)
    }

    func testMapsGraphicMediaLabelToGraphicWarning() {
        let display = PostDisplay(FeedViewPost(post: post(labels: [Label(val: "graphic-media", src: "did:plc:labeler")])))

        XCTAssertEqual(display.mediaWarning, .graphic)
    }

    func testMapsSexualAndNudityLabelsToAdultWarning() {
        XCTAssertEqual(PostDisplay(FeedViewPost(post: post(labels: [Label(val: "sexual")]))).mediaWarning, .adult)
        XCTAssertEqual(PostDisplay(FeedViewPost(post: post(labels: [Label(val: "nudity")]))).mediaWarning, .adult)
    }

    func testPostWithoutSensitiveLabelHasNoMediaWarning() {
        XCTAssertNil(PostDisplay(FeedViewPost(post: post())).mediaWarning)
        XCTAssertNil(PostDisplay(FeedViewPost(post: post(labels: [Label(val: "spam")]))).mediaWarning)
    }

    func testNegatedLabelDoesNotTriggerMediaWarning() {
        let display = PostDisplay(FeedViewPost(post: post(labels: [Label(val: "porn", src: "did:plc:labeler", neg: true)])))

        XCTAssertNil(display.mediaWarning)
    }

    func testMapsExternalEmbedToLinkCard() {
        let postView = PostView(
            uri: "at://did:plc:alice/app.bsky.feed.post/aaa",
            cid: "cid",
            author: ProfileViewBasic(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatar: nil),
            record: PostRecord(text: "see https://example.com/article", createdAt: "2026-06-04T12:00:00.000Z"),
            replyCount: nil, repostCount: nil, likeCount: nil,
            indexedAt: "2026-06-04T12:00:01.000Z",
            embed: PostEmbed(
                images: [],
                external: EmbedExternal(
                    uri: "https://example.com/article",
                    title: "An Article",
                    description: "Worth reading.",
                    thumb: "https://cdn.example/thumb.jpg"
                )
            )
        )

        let display = PostDisplay(FeedViewPost(post: postView))

        XCTAssertEqual(display.linkCard?.url, URL(string: "https://example.com/article"))
        XCTAssertEqual(display.linkCard?.title, "An Article")
        XCTAssertEqual(display.linkCard?.description, "Worth reading.")
        XCTAssertEqual(display.linkCard?.thumbURL, URL(string: "https://cdn.example/thumb.jpg"))
        XCTAssertEqual(display.linkCard?.host, "example.com")
    }

    func testPostWithoutExternalEmbedHasNilLinkCard() {
        let display = PostDisplay(FeedViewPost(post: post()))
        XCTAssertNil(display.linkCard)
    }

    func testMapsCidAndViewerState() {
        let postView = PostView(
            uri: "at://did:plc:alice/app.bsky.feed.post/aaa",
            cid: "bafyreialice",
            author: ProfileViewBasic(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatar: nil),
            record: PostRecord(text: "hi", createdAt: "2026-06-04T12:00:00.000Z"),
            replyCount: nil, repostCount: nil, likeCount: nil,
            indexedAt: "2026-06-04T12:00:01.000Z",
            viewer: PostViewerState(like: "at://did:plc:me/app.bsky.feed.like/xyz", repost: nil)
        )

        let display = PostDisplay(FeedViewPost(post: postView))

        XCTAssertEqual(display.cid, "bafyreialice")
        XCTAssertEqual(display.viewerLikeURI, "at://did:plc:me/app.bsky.feed.like/xyz")
        XCTAssertTrue(display.isLiked)
        XCTAssertNil(display.viewerRepostURI)
        XCTAssertFalse(display.isReposted)
    }

    func testNoViewerMapsToNotLikedNotReposted() {
        let display = PostDisplay(FeedViewPost(post: post()))
        XCTAssertNil(display.viewerLikeURI)
        XCTAssertNil(display.viewerRepostURI)
        XCTAssertFalse(display.isLiked)
        XCTAssertFalse(display.isReposted)
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

    func testMapsImageAspectRatio() {
        let embed = PostEmbed(images: [
            EmbedImage(thumb: "https://cdn.example/t1.jpg", fullsize: "https://cdn.example/f1.jpg", alt: "wide",
                       aspectRatio: ImageAspectRatio(width: 1600, height: 900)),
            EmbedImage(thumb: "https://cdn.example/t2.jpg", fullsize: "https://cdn.example/f2.jpg", alt: "no ratio")
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

        XCTAssertEqual(display.images[0].aspectRatio ?? 0, 1600.0 / 900.0, accuracy: 0.0001)
        XCTAssertNil(display.images[1].aspectRatio)
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

    func testMapsThreadViewPostWithParent() {
        let parent = post(
            uri: "at://did:plc:alice/app.bsky.feed.post/root",
            handle: "alice.bsky.social",
            displayName: "Alice",
            text: "起点の投稿"
        )
        let focus = post(
            uri: "at://did:plc:bob/app.bsky.feed.post/reply",
            handle: "bob.bsky.social",
            displayName: "Bob",
            text: "返信"
        )

        let display = PostDisplay(ThreadViewPost(post: focus, parentPost: parent))

        XCTAssertEqual(display.id, "at://did:plc:bob/app.bsky.feed.post/reply")
        XCTAssertEqual(display.body, "返信")
        XCTAssertEqual(display.replyParent?.post.authorHandle, "alice.bsky.social")
        XCTAssertEqual(display.replyParent?.post.body, "起点の投稿")
    }

    func testMapsThreadViewPostFullAncestorChain() {
        let root = post(uri: "at://p/root", handle: "alice.bsky.social", text: "親")
        let mid = post(uri: "at://p/mid", handle: "bob.bsky.social", text: "子")
        let leaf = post(uri: "at://p/leaf", handle: "carol.bsky.social", text: "孫")
        let node = ThreadViewPost(
            post: leaf,
            parent: ThreadViewPost(post: mid, parent: ThreadViewPost(post: root))
        )

        let display = PostDisplay(node)

        XCTAssertEqual(display.id, "at://p/leaf")
        XCTAssertEqual(display.replyParent?.post.id, "at://p/mid")
        XCTAssertEqual(display.replyParent?.post.replyParent?.post.id, "at://p/root")
        XCTAssertNil(display.replyParent?.post.replyParent?.post.replyParent)
    }

    func testMapsThreadViewPostWithoutParent() {
        let focus = post(uri: "at://did:plc:alice/app.bsky.feed.post/root", text: "起点")
        let display = PostDisplay(ThreadViewPost(post: focus, parentPost: nil))
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

    func testMapsFacetsIntoBodySegments() {
        let text = "see https://example.com #swift"
        let postView = PostView(
            uri: "at://did:plc:alice/app.bsky.feed.post/aaa",
            cid: "cid",
            author: ProfileViewBasic(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatar: nil),
            record: PostRecord(
                text: text,
                createdAt: "2026-06-04T12:00:00.000Z",
                facets: [
                    Facet(byteStart: 4, byteEnd: 23, features: [.link(uri: "https://example.com")]),
                    Facet(byteStart: 24, byteEnd: 30, features: [.tag(tag: "swift")])
                ]
            ),
            replyCount: nil, repostCount: nil, likeCount: nil,
            indexedAt: "2026-06-04T12:00:01.000Z"
        )

        let display = PostDisplay(FeedViewPost(post: postView))

        XCTAssertEqual(display.body, text)
        XCTAssertEqual(display.bodySegments.map(\.kind), [.text, .link, .text, .tag])
        XCTAssertEqual(display.bodySegments[1].url, URL(string: "https://example.com"))
        XCTAssertEqual(display.bodySegments[3].text, "#swift")
    }

    func testBodySegmentsFallBackToPlainTextWhenNoFacets() {
        let display = PostDisplay(FeedViewPost(post: post(text: "plain body")))
        XCTAssertEqual(display.bodySegments.map(\.kind), [.text])
        XCTAssertEqual(display.bodySegments.map(\.text), ["plain body"])
    }

    func testMapsVideoEmbedToPostVideo() {
        let postView = PostView(
            uri: "at://did:plc:alice/app.bsky.feed.post/aaa",
            cid: "cid",
            author: ProfileViewBasic(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatar: nil),
            record: PostRecord(text: "watch this", createdAt: "2026-06-04T12:00:00.000Z"),
            replyCount: nil, repostCount: nil, likeCount: nil,
            indexedAt: "2026-06-04T12:00:01.000Z",
            embed: PostEmbed(
                images: [],
                video: EmbedVideo(
                    playlist: "https://video.example/playlist.m3u8",
                    thumbnail: "https://video.example/poster.jpg",
                    alt: "a dog",
                    aspectRatio: ImageAspectRatio(width: 1280, height: 720)
                )
            )
        )

        let display = PostDisplay(FeedViewPost(post: postView))
        let video = display.video

        XCTAssertEqual(video?.thumbURL, URL(string: "https://video.example/poster.jpg"))
        XCTAssertEqual(video?.alt, "a dog")
        XCTAssertEqual(video?.aspectRatio, 1280.0 / 720.0)
    }

    func testMapsRecordEmbedToQuotedPost() {
        let postView = PostView(
            uri: "at://did:plc:alice/app.bsky.feed.post/aaa",
            cid: "cid",
            author: ProfileViewBasic(did: "did:plc:alice", handle: "alice.bsky.social", displayName: "Alice", avatar: nil),
            record: PostRecord(text: "check this out", createdAt: "2026-06-04T12:00:00.000Z"),
            replyCount: nil, repostCount: nil, likeCount: nil,
            indexedAt: "2026-06-04T12:00:01.000Z",
            embed: PostEmbed(
                images: [],
                record: EmbedRecord(
                    uri: "at://did:plc:quoted/app.bsky.feed.post/qqq",
                    cid: "bafyquoted",
                    author: ProfileViewBasic(
                        did: "did:plc:quoted",
                        handle: "quoted.bsky.social",
                        displayName: "Quoted Author",
                        avatar: "https://cdn.example/quoted.jpg"
                    ),
                    value: PostRecord(text: "the quoted text", createdAt: "2026-06-10T08:00:00.000Z"),
                    embeds: [
                        PostEmbed(images: [
                            EmbedImage(thumb: "https://cdn.example/q-thumb.jpg", fullsize: "https://cdn.example/q-full.jpg", alt: "pic")
                        ])
                    ]
                )
            )
        )

        let display = PostDisplay(FeedViewPost(post: postView))
        let quote = display.quote

        XCTAssertEqual(quote?.id, "at://did:plc:quoted/app.bsky.feed.post/qqq")
        XCTAssertEqual(quote?.authorDisplayName, "Quoted Author")
        XCTAssertEqual(quote?.authorHandle, "quoted.bsky.social")
        XCTAssertEqual(quote?.avatarURL, URL(string: "https://cdn.example/quoted.jpg"))
        XCTAssertEqual(quote?.body, "the quoted text")
        // Parsed, not an epoch-0 fallback.
        XCTAssertGreaterThan(quote?.createdAt.timeIntervalSince1970 ?? 0, 1_700_000_000)
        XCTAssertEqual(quote?.images.first?.thumbURL, URL(string: "https://cdn.example/q-thumb.jpg"))
    }

    func testQuoteAndVideoAreNilWithoutMatchingEmbeds() {
        let display = PostDisplay(FeedViewPost(post: post()))
        XCTAssertNil(display.quote)
        XCTAssertNil(display.video)
    }

    func testParsesFractionalAndWholeSecondTimestamps() {
        let fractional = PostDisplay(FeedViewPost(post: post(createdAt: "2026-06-04T12:00:00.000Z")))
        let whole = PostDisplay(FeedViewPost(post: post(createdAt: "2026-06-04T12:00:00Z")))

        XCTAssertEqual(fractional.createdAt, whole.createdAt)
        // Parsed, not the epoch-0 fallback used for unparseable timestamps.
        XCTAssertGreaterThan(fractional.createdAt.timeIntervalSince1970, 1_700_000_000)
    }
}
