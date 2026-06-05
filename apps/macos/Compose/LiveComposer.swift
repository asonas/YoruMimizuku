import Foundation
import BlueskyCore
import YoruMimizukuKit

/// Live `PostSubmitting`: builds a `LiveServiceContext`, runs `PostService.createPost`
/// with the draft's text/images/reply parent, and persists any refreshed tokens.
struct LiveComposer: PostSubmitting {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    func submit(_ draft: PostDraft) async throws -> PostResult {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = PostService(
            sender: context.sender, metadataResolver: context.metadataResolver, config: context.config
        )
        let images = draft.images.map { (data: $0.data, mimeType: $0.mimeType, alt: $0.alt) }
        let result = try await service.createPost(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            did: context.account.did,
            text: draft.text,
            images: images,
            replyParentURI: draft.replyParentURI,
            quote: draft.quote
        )
        try context.persist(result.refreshed)
        return PostResult(uri: result.response.uri, cid: result.response.cid)
    }
}
