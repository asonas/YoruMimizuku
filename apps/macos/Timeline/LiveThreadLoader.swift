import Foundation
import BlueskyCore
import YoruMimizukuKit

/// Live `ThreadLoading`: wires the real `ThreadService` through a
/// `LiveServiceContext`, fetches a post's thread, persists any refreshed tokens,
/// and maps the focused post (with its immediate parent) into a `PostDisplay`.
struct LiveThreadLoader: ThreadLoading {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    func loadThread(uri: String) async throws -> PostDisplay {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = ThreadService(
            sender: context.sender, metadataResolver: context.metadataResolver, config: context.config
        )

        let result = try await service.getPostThread(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            uri: uri
        )

        try context.persist(result.refreshed)

        return PostDisplay(result.response.thread)
    }
}
