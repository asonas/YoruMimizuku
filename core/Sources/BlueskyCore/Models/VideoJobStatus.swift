import Foundation

/// The status of a video processing job (`app.bsky.video.defs#jobStatus`).
/// `app.bsky.video.uploadVideo` returns this object directly, while
/// `app.bsky.video.getJobStatus` wraps it under a `jobStatus` key — this decoder
/// accepts both shapes. The processed `blob` appears once `state` reaches
/// `JOB_STATE_COMPLETED`; it is then embedded into the post as `app.bsky.embed.video`.
public struct VideoJobStatus: Decodable, Equatable, Sendable {
    public let jobId: String
    public let did: String?
    public let state: String
    public let progress: Int?
    public let blob: BlobRef?
    public let error: String?
    public let message: String?

    /// The job finished successfully and a blob is available to embed.
    public var isCompleted: Bool { blob != nil || state == "JOB_STATE_COMPLETED" }
    /// The job failed; `error` / `message` describe why.
    public var isFailed: Bool { state == "JOB_STATE_FAILED" }

    public init(
        jobId: String, did: String? = nil, state: String, progress: Int? = nil,
        blob: BlobRef? = nil, error: String? = nil, message: String? = nil
    ) {
        self.jobId = jobId
        self.did = did
        self.state = state
        self.progress = progress
        self.blob = blob
        self.error = error
        self.message = message
    }

    private enum TopKeys: String, CodingKey { case jobStatus }
    private enum Keys: String, CodingKey { case jobId, did, state, progress, blob, error, message }

    public init(from decoder: Decoder) throws {
        // getJobStatus wraps the status in `jobStatus`; uploadVideo returns it bare.
        if let top = try? decoder.container(keyedBy: TopKeys.self), top.contains(.jobStatus) {
            self = try VideoJobStatus(top.nestedContainer(keyedBy: Keys.self, forKey: .jobStatus))
        } else {
            self = try VideoJobStatus(decoder.container(keyedBy: Keys.self))
        }
    }

    private init(_ c: KeyedDecodingContainer<Keys>) throws {
        jobId = try c.decode(String.self, forKey: .jobId)
        did = try c.decodeIfPresent(String.self, forKey: .did)
        state = try c.decode(String.self, forKey: .state)
        progress = try c.decodeIfPresent(Int.self, forKey: .progress)
        blob = try c.decodeIfPresent(BlobRef.self, forKey: .blob)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        message = try c.decodeIfPresent(String.self, forKey: .message)
    }
}
