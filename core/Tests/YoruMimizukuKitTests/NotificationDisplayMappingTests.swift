import XCTest
import BlueskyCore
@testable import YoruMimizukuKit

final class NotificationDisplayMappingTests: XCTestCase {
    private func notification(
        reason: NotificationReason,
        text: String?,
        displayName: String? = "Bob",
        isRead: Bool = false
    ) -> BskyNotification {
        BskyNotification(
            uri: "at://did:plc:bob/app.bsky.feed.like/aaa",
            cid: "cid123",
            author: ProfileViewBasic(
                did: "did:plc:bob", handle: "bob.bsky.social",
                displayName: displayName, avatar: "https://cdn.example/bob.jpg"
            ),
            reason: reason,
            reasonSubject: "at://did:plc:me/app.bsky.feed.post/mine",
            record: NotificationRecord(text: text),
            isRead: isRead,
            indexedAt: "2026-06-04T12:00:00.000Z"
        )
    }

    func testMapsAuthorReasonAndText() {
        let display = NotificationDisplay(notification(reason: .reply, text: "nice work!"))

        XCTAssertEqual(display.reason, .reply)
        XCTAssertEqual(display.authorDisplayName, "Bob")
        XCTAssertEqual(display.authorHandle, "bob.bsky.social")
        XCTAssertEqual(display.avatarURL, URL(string: "https://cdn.example/bob.jpg"))
        XCTAssertEqual(display.text, "nice work!")
        XCTAssertFalse(display.isRead)
    }

    func testFallsBackToHandleWhenNoDisplayName() {
        let display = NotificationDisplay(notification(reason: .follow, text: nil, displayName: nil))
        XCTAssertEqual(display.authorDisplayName, "bob.bsky.social")
        XCTAssertNil(display.text)
    }

    func testParsesIndexedAtTimestamp() {
        let display = NotificationDisplay(notification(reason: .like, text: nil))
        XCTAssertEqual(display.createdAt, ISO8601DateFormatter().date(from: "2026-06-04T12:00:00Z"))
    }

    func testIdentityCombinesUriAndCid() {
        let display = NotificationDisplay(notification(reason: .like, text: nil))
        XCTAssertEqual(display.id, "at://did:plc:bob/app.bsky.feed.like/aaa|cid123")
    }

    func testMapsReasonSubjectToSubjectURI() {
        let display = NotificationDisplay(notification(reason: .like, text: nil))
        XCTAssertEqual(display.subjectURI, "at://did:plc:me/app.bsky.feed.post/mine")
    }
}
