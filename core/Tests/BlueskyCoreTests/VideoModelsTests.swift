import XCTest
@testable import BlueskyCore

final class VideoModelsTests: XCTestCase {
    private func json(_ s: String) -> Data { Data(s.utf8) }

    // 1. ServiceAuthResponse decodes { "token": "..." }.
    func testServiceAuthResponseDecodesToken() throws {
        let data = json(##"{"token":"jwt.abc.def"}"##)
        let decoded = try JSONDecoder().decode(ServiceAuthResponse.self, from: data)
        XCTAssertEqual(decoded.token, "jwt.abc.def")
    }

    // 2. Completed getJobStatus (wrapped, with blob) decodes and exposes the blob.
    func testVideoJobStatusCompletedWithBlob() throws {
        let data = json(##"""
        {"jobStatus":{"jobId":"job1","did":"did:plc:me","state":"JOB_STATE_COMPLETED",
         "blob":{"$type":"blob","ref":{"$link":"bafyvideo"},"mimeType":"video/mp4","size":1234}}}
        """##)
        let status = try JSONDecoder().decode(VideoJobStatus.self, from: data)
        XCTAssertEqual(status.jobId, "job1")
        XCTAssertTrue(status.isCompleted)
        XCTAssertFalse(status.isFailed)
        XCTAssertEqual(status.blob?.cid, "bafyvideo")
        XCTAssertEqual(status.blob?.mimeType, "video/mp4")
    }

    // 3. In-progress status (bare, no blob) decodes and is neither completed nor failed.
    func testVideoJobStatusInProgressBare() throws {
        let data = json(##"""
        {"jobId":"job2","did":"did:plc:me","state":"JOB_STATE_ENCODING","progress":42}
        """##)
        let status = try JSONDecoder().decode(VideoJobStatus.self, from: data)
        XCTAssertEqual(status.jobId, "job2")
        XCTAssertEqual(status.progress, 42)
        XCTAssertNil(status.blob)
        XCTAssertFalse(status.isCompleted)
        XCTAssertFalse(status.isFailed)
    }

    // 4. Failed status decodes its error/message and reports isFailed.
    func testVideoJobStatusFailed() throws {
        let data = json(##"""
        {"jobStatus":{"jobId":"job3","state":"JOB_STATE_FAILED","error":"invalid_format",
         "message":"unsupported codec"}}
        """##)
        let status = try JSONDecoder().decode(VideoJobStatus.self, from: data)
        XCTAssertTrue(status.isFailed)
        XCTAssertFalse(status.isCompleted)
        XCTAssertEqual(status.error, "invalid_format")
        XCTAssertEqual(status.message, "unsupported codec")
    }

    // 5. VideoWrite encodes app.bsky.embed.video with the blob, aspectRatio, and alt.
    func testVideoWriteEncodesEmbed() throws {
        let write = VideoWrite(
            video: BlobRef(cid: "bafyvideo", mimeType: "video/mp4", size: 100),
            aspectRatio: ImageAspectRatio(width: 1920, height: 1080),
            alt: "a clip"
        )
        let data = try JSONEncoder().encode(write)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["$type"] as? String, "app.bsky.embed.video")
        XCTAssertEqual(obj["alt"] as? String, "a clip")
        let blob = try XCTUnwrap(obj["video"] as? [String: Any])
        XCTAssertEqual(blob["$type"] as? String, "blob")
        let ratio = try XCTUnwrap(obj["aspectRatio"] as? [String: Any])
        XCTAssertEqual(ratio["width"] as? Int, 1920)
        XCTAssertEqual(ratio["height"] as? Int, 1080)
    }

    // 6. PostEmbedWrite.video and .recordWithVideo encode the right $type.
    func testPostEmbedWriteVideoCases() throws {
        let video = VideoWrite(video: BlobRef(cid: "v", mimeType: "video/mp4", size: 1))

        let videoEmbed = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(PostEmbedWrite.video(video))
        ) as? [String: Any]
        XCTAssertEqual(videoEmbed?["$type"] as? String, "app.bsky.embed.video")

        let quoteVideo = PostEmbedWrite.recordWithVideo(
            record: StrongRef(uri: "at://x/app.bsky.feed.post/1", cid: "c"), video: video
        )
        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(quoteVideo)) as? [String: Any]
        )
        XCTAssertEqual(obj["$type"] as? String, "app.bsky.embed.recordWithMedia")
        let media = try XCTUnwrap(obj["media"] as? [String: Any])
        XCTAssertEqual(media["$type"] as? String, "app.bsky.embed.video")
        XCTAssertNotNil(obj["record"])
    }
}
