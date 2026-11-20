import XCTest
@testable import BlueskyCore

final class ListMembershipModelsTests: XCTestCase {
    func testListsWithMembershipDecodeListsAndTheMembershipItem() throws {
        let body = Data(##"""
        {
          "listsWithMembership": [
            {
              "list": {
                "uri": "at://did:plc:me/app.bsky.graph.list/close",
                "cid": "bafy",
                "name": "近しい人",
                "purpose": "app.bsky.graph.defs#curatelist",
                "creator": { "did": "did:plc:me", "handle": "me.example" },
                "indexedAt": "2026-11-20T00:00:00.000Z"
              },
              "listItem": {
                "uri": "at://did:plc:me/app.bsky.graph.listitem/3k",
                "subject": { "did": "did:plc:alice", "handle": "alice.example" }
              }
            },
            {
              "list": {
                "uri": "at://did:plc:me/app.bsky.graph.list/swift",
                "cid": "bafy",
                "name": "Swift",
                "purpose": "app.bsky.graph.defs#curatelist",
                "creator": { "did": "did:plc:me", "handle": "me.example" },
                "indexedAt": "2026-11-20T00:00:00.000Z"
              }
            }
          ]
        }
        """##.utf8)

        let response = try JSONDecoder().decode(ListsWithMembershipResponse.self, from: body)

        XCTAssertEqual(response.listsWithMembership.map(\.list.name), ["近しい人", "Swift"])
        XCTAssertEqual(response.listsWithMembership.map(\.list.purpose), ["app.bsky.graph.defs#curatelist", "app.bsky.graph.defs#curatelist"])
        XCTAssertEqual(response.listsWithMembership.map(\.listItem?.uri), ["at://did:plc:me/app.bsky.graph.listitem/3k", nil])
    }

    func testListItemRecordEncodesTypeSubjectListAndDate() throws {
        let record = ListItemRecordWrite(
            subject: "did:plc:alice", list: "at://did:plc:me/app.bsky.graph.list/close", createdAt: "2026-11-20T00:00:00.000Z"
        )

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: String])

        XCTAssertEqual(object, [
            "$type": "app.bsky.graph.listitem",
            "subject": "did:plc:alice",
            "list": "at://did:plc:me/app.bsky.graph.list/close",
            "createdAt": "2026-11-20T00:00:00.000Z"
        ])
    }
}
