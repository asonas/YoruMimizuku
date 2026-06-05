import XCTest
import BlueskyCore
@testable import YoruMimizukuKit

final class NotificationGroupTests: XCTestCase {
    private func display(
        id: String,
        reason: NotificationReason,
        handle: String,
        subjectURI: String?,
        text: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        isRead: Bool = false
    ) -> NotificationDisplay {
        NotificationDisplay(
            id: id,
            reason: reason,
            authorDisplayName: handle,
            authorHandle: handle,
            avatarURL: nil,
            text: text,
            createdAt: createdAt,
            isRead: isRead,
            subjectURI: subjectURI
        )
    }

    func testGroupsLikesOnSameSubjectIntoOneGroupWithMultipleActors() {
        let items = [
            display(id: "1", reason: .like, handle: "a", subjectURI: "at://post/1"),
            display(id: "2", reason: .like, handle: "b", subjectURI: "at://post/1")
        ]
        let groups = NotificationGroup.group(items)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].reason, .like)
        XCTAssertEqual(groups[0].actors.map(\.handle), ["a", "b"])
        XCTAssertEqual(groups[0].subjectURI, "at://post/1")
    }

    func testLikeAndRepostOnSameSubjectAreSeparateGroups() {
        let items = [
            display(id: "1", reason: .like, handle: "a", subjectURI: "at://post/1"),
            display(id: "2", reason: .repost, handle: "a", subjectURI: "at://post/1")
        ]
        let groups = NotificationGroup.group(items)
        XCTAssertEqual(groups.count, 2)
    }

    func testRepliesAreNotGrouped() {
        let items = [
            display(id: "1", reason: .reply, handle: "a", subjectURI: "at://post/1", text: "hi"),
            display(id: "2", reason: .reply, handle: "b", subjectURI: "at://post/1", text: "yo")
        ]
        let groups = NotificationGroup.group(items)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].actors.count, 1)
    }

    func testPreservesFirstOccurrenceOrder() {
        let items = [
            display(id: "1", reason: .like, handle: "a", subjectURI: "at://post/1"),
            display(id: "2", reason: .follow, handle: "b", subjectURI: nil),
            display(id: "3", reason: .like, handle: "c", subjectURI: "at://post/1")
        ]
        let groups = NotificationGroup.group(items)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].reason, .like)
        XCTAssertEqual(groups[0].actors.map(\.handle), ["a", "c"])
        XCTAssertEqual(groups[1].reason, .follow)
    }

    func testGroupIsReadOnlyWhenAllItemsRead() {
        let items = [
            display(id: "1", reason: .like, handle: "a", subjectURI: "at://post/1", isRead: true),
            display(id: "2", reason: .like, handle: "b", subjectURI: "at://post/1", isRead: false)
        ]
        let groups = NotificationGroup.group(items)
        XCTAssertFalse(groups[0].isRead)
    }

    func testLatestCreatedAtIsMaxOfGroup() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let items = [
            display(id: "1", reason: .like, handle: "a", subjectURI: "at://post/1", createdAt: newer),
            display(id: "2", reason: .like, handle: "b", subjectURI: "at://post/1", createdAt: older)
        ]
        let groups = NotificationGroup.group(items)
        XCTAssertEqual(groups[0].latestCreatedAt, newer)
    }

    func testWithSubjectAttachesSnippet() {
        let items = [display(id: "1", reason: .like, handle: "a", subjectURI: "at://post/1")]
        let group = NotificationGroup.group(items)[0]
        let url = URL(string: "https://cdn.example/thumb.jpg")
        let updated = group.withSubject(text: "hello", imageURL: url)
        XCTAssertEqual(updated.subjectText, "hello")
        XCTAssertEqual(updated.subjectImageURL, url)
    }
}
