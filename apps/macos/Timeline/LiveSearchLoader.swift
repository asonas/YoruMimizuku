import Foundation
import os
import BlueskyCore
import YoruMimizukuKit
import PlatformApple

/// Live `TimelineLoading` for a saved filter: wires the real `SearchService`
/// through a `LiveServiceContext`, fetches a page of search results for the
/// captured `query` (passing the cursor for infinite scroll), persists any
/// refreshed tokens, and maps the posts into `PostDisplay` rows. Lets each filter
/// tab reuse `TimelineViewModel` unchanged.
struct LiveSearchLoader: TimelineLoading {
    let accountManager: AccountManager
    let query: String
    let config: OAuthClientConfig

    init(accountManager: AccountManager, query: String, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.query = query
        self.config = config
    }

    func loadPage(cursor: String?) async throws -> TimelinePage {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = SearchService(
            sender: context.sender, metadataResolver: context.metadataResolver, config: context.config
        )

        let result = try await service.searchPosts(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            query: query,
            cursor: cursor
        )

        try context.persist(result.refreshed)

        let posts = result.response.posts.map { PostDisplay(postView: $0) }
        return TimelinePage(posts: posts, cursor: result.response.cursor)
    }
}
