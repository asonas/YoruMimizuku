import Foundation
import BlueskyCore
import YoruMimizukuKit

/// Live `PostSubmitting`: builds a `LiveServiceContext`, runs `PostService.createPost`
/// with the draft's text/images/reply parent, and persists any refreshed tokens.
/// When the draft carries a video, it first obtains a service-auth token, uploads
/// the video to the Bluesky video service, and waits for processing — then embeds
/// the resulting blob in the post.
struct LiveComposer: PostSubmitting {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    enum ComposeError: Error { case cannotDeriveVideoAudience }

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    func submit(_ draft: PostDraft) async throws -> PostResult {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = PostService(
            sender: context.sender, metadataResolver: context.metadataResolver, config: context.config, refreshGate: context.refreshGate
        )

        // Thread the latest tokens forward: getServiceAuth may refresh, and the
        // refresh token is single-use, so createPost must continue from the new one.
        var accessToken = context.account.accessToken
        var refreshToken = context.account.refreshToken

        var videoArg: (blob: BlobRef, aspectRatio: ImageAspectRatio?, alt: String)? = nil
        if let video = draft.video {
            guard let audience = VideoServiceConfig.audience(forPDS: context.account.pds) else {
                throw ComposeError.cannotDeriveVideoAudience
            }
            let auth = try await service.getServiceAuth(
                pds: context.account.pds, issuer: context.issuer,
                accessToken: accessToken, refreshToken: refreshToken,
                audience: audience, lxm: "com.atproto.repo.uploadBlob"
            )
            if let refreshedTokens = auth.refreshed {
                try context.persist(refreshedTokens)
                accessToken = refreshedTokens.accessToken
                refreshToken = refreshedTokens.refreshToken ?? refreshToken
            }
            let videoService = VideoUploadService(http: URLSessionHTTPClient())
            let job = try await videoService.uploadVideo(
                serviceToken: auth.token, did: context.account.did,
                name: video.filename, data: video.data, mimeType: video.mimeType
            )
            let blob = try await videoService.pollUntilComplete(jobId: job.jobId, serviceToken: auth.token)
            let aspectRatio = video.width.flatMap { w in video.height.map { ImageAspectRatio(width: w, height: $0) } }
            videoArg = (blob: blob, aspectRatio: aspectRatio, alt: video.alt)
        }

        let images = draft.images.map { (data: $0.data, mimeType: $0.mimeType, alt: $0.alt) }
        let result = try await service.createPost(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: accessToken,
            refreshToken: refreshToken,
            did: context.account.did,
            text: draft.text,
            images: images,
            replyParentURI: draft.replyParentURI,
            quote: draft.quote,
            video: videoArg
        )
        try context.persist(result.refreshed)
        return PostResult(uri: result.response.uri, cid: result.response.cid)
    }
}
