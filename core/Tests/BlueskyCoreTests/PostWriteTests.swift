import XCTest
@testable import BlueskyCore

final class PostWriteTests: XCTestCase {
    private func encodeJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testFacetWriteEncodesIndexAndLinkFeature() throws {
        let facet = FacetWrite(byteStart: 4, byteEnd: 23, feature: .link(uri: "https://example.com"))
        let json = try encodeJSON(facet)
        let index = try XCTUnwrap(json["index"] as? [String: Any])
        XCTAssertEqual(index["byteStart"] as? Int, 4)
        XCTAssertEqual(index["byteEnd"] as? Int, 23)
        let features = try XCTUnwrap(json["features"] as? [[String: Any]])
        XCTAssertEqual(features.first?["$type"] as? String, "app.bsky.richtext.facet#link")
        XCTAssertEqual(features.first?["uri"] as? String, "https://example.com")
    }

    func testPostRecordWriteEncodesTypeAndOmitsEmptyFacets() throws {
        let record = PostRecordWrite(text: "hi", createdAt: "2026-06-05T00:00:00.000Z",
                                     facets: [], embed: nil, reply: nil)
        let json = try encodeJSON(record)
        XCTAssertEqual(json["$type"] as? String, "app.bsky.feed.post")
        XCTAssertEqual(json["text"] as? String, "hi")
        XCTAssertNil(json["facets"])
        XCTAssertNil(json["embed"])
        XCTAssertNil(json["reply"])
    }

    func testImagesEmbedEncodesBlobRef() throws {
        let blob = BlobRef(cid: "bafycid", mimeType: "image/jpeg", size: 1234)
        let embed = ImagesEmbedWrite(images: [ImageWrite(image: blob, alt: "a cat")])
        let json = try encodeJSON(embed)
        XCTAssertEqual(json["$type"] as? String, "app.bsky.embed.images")
        let images = try XCTUnwrap(json["images"] as? [[String: Any]])
        XCTAssertEqual(images.first?["alt"] as? String, "a cat")
        let image = try XCTUnwrap(images.first?["image"] as? [String: Any])
        XCTAssertEqual(image["$type"] as? String, "blob")
        XCTAssertEqual(image["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(image["size"] as? Int, 1234)
        let ref = try XCTUnwrap(image["ref"] as? [String: Any])
        XCTAssertEqual(ref["$link"] as? String, "bafycid")
    }

    func testUploadBlobResponseDecodes() throws {
        let data = Data(##"""
        {"blob":{"$type":"blob","ref":{"$link":"bafycid"},"mimeType":"image/png","size":42}}
        """##.utf8)
        let decoded = try JSONDecoder().decode(UploadBlobResponse.self, from: data)
        XCTAssertEqual(decoded.blob.cid, "bafycid")
        XCTAssertEqual(decoded.blob.mimeType, "image/png")
        XCTAssertEqual(decoded.blob.size, 42)
    }
}
