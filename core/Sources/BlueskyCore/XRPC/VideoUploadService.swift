import Foundation

/// Where and how to reach the Bluesky video service.
public struct VideoServiceConfig: Sendable {
    /// The video service host. Uploads and job-status polls go here (not the PDS).
    public let serviceURL: URL

    public init(serviceURL: URL = URL(string: "https://video.bsky.app")!) {
        self.serviceURL = serviceURL
    }

    /// The service-auth audience used to authorize a blob upload via the user's PDS:
    /// `did:web:<PDS host>` (e.g. `did:web:morel.us-east.host.bsky.network`).
    public static func audience(forPDS pds: URL) -> String? {
        guard let host = pds.host else { return nil }
        return "did:web:\(host)"
    }
}

/// Errors raised while uploading a video to the Bluesky video service.
public enum VideoUploadError: Error, Equatable, Sendable {
    /// The processing job ended in `JOB_STATE_FAILED`.
    case processingFailed(state: String, message: String?)
    /// Polling exhausted `maxAttempts` before a blob was ready.
    case timedOut
}

/// Uploads a video to the Bluesky video service and polls until it is processed.
///
/// Unlike image `uploadBlob` (a single DPoP-bound POST to the PDS), video upload
/// is multi-step and targets a *different* host with a **Bearer** service-auth
/// token rather than DPoP, so this talks to the raw `HTTPClient` directly:
/// 1. (caller) obtain a service-auth token from the PDS (`getServiceAuth`).
/// 2. `uploadVideo` — POST the bytes to the video service; returns a job.
/// 3. `pollUntilComplete` — poll `getJobStatus` until the processed blob is ready.
/// The resulting `BlobRef` is then embedded as `app.bsky.embed.video`.
public struct VideoUploadService: Sendable {
    private let http: HTTPClient
    private let config: VideoServiceConfig
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        http: HTTPClient,
        config: VideoServiceConfig = VideoServiceConfig(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.http = http
        self.config = config
        self.sleep = sleep
    }

    /// POST the raw video bytes to `app.bsky.video.uploadVideo` on the video service,
    /// authorized by the Bearer service-auth `token`. Returns the initial job status.
    public func uploadVideo(
        serviceToken: String, did: String, name: String, data: Data, mimeType: String
    ) async throws -> VideoJobStatus {
        let endpoint = config.serviceURL.appendingPathComponent("xrpc/app.bsky.video.uploadVideo")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL(endpoint.absoluteString)
        }
        components.queryItems = [
            URLQueryItem(name: "did", value: did),
            URLQueryItem(name: "name", value: name),
        ]
        guard let url = components.url else { throw XRPCError.invalidURL(endpoint.absoluteString) }
        let response = try await http.send(HTTPRequest(
            url: url, method: .post,
            headers: [
                "Authorization": "Bearer \(serviceToken)",
                "Content-Type": mimeType,
                "Accept": "application/json",
            ],
            body: data
        ))
        return try Self.decode(response)
    }

    /// GET `app.bsky.video.getJobStatus` for one poll of the job's state.
    public func getJobStatus(jobId: String, serviceToken: String) async throws -> VideoJobStatus {
        let endpoint = config.serviceURL.appendingPathComponent("xrpc/app.bsky.video.getJobStatus")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw XRPCError.invalidURL(endpoint.absoluteString)
        }
        components.queryItems = [URLQueryItem(name: "jobId", value: jobId)]
        guard let url = components.url else { throw XRPCError.invalidURL(endpoint.absoluteString) }
        let response = try await http.send(HTTPRequest(
            url: url, method: .get,
            headers: ["Authorization": "Bearer \(serviceToken)", "Accept": "application/json"]
        ))
        return try Self.decode(response)
    }

    /// Poll `getJobStatus` until the processed blob is available, sleeping `interval`
    /// between attempts. Throws `VideoUploadError.processingFailed` on a failed job
    /// and `.timedOut` if `maxAttempts` is reached first.
    public func pollUntilComplete(
        jobId: String, serviceToken: String, maxAttempts: Int = 90, interval: Duration = .seconds(2)
    ) async throws -> BlobRef {
        for attempt in 0..<maxAttempts {
            let status = try await getJobStatus(jobId: jobId, serviceToken: serviceToken)
            if let blob = status.blob { return blob }
            if status.isFailed {
                throw VideoUploadError.processingFailed(state: status.state, message: status.message ?? status.error)
            }
            if attempt < maxAttempts - 1 { try await sleep(interval) }
        }
        throw VideoUploadError.timedOut
    }

    private static func decode<T: Decodable>(_ response: HTTPResponse) throws -> T {
        guard (200..<300).contains(response.statusCode) else {
            let errorBody = try? JSONDecoder().decode(XRPCErrorResponse.self, from: response.body)
            throw XRPCError.requestFailed(status: response.statusCode, body: errorBody)
        }
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw XRPCError.decodingFailed(String(describing: error))
        }
    }
}
