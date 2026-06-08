import Foundation
import os
import BlueskyCore
import YoruMimizukuKit
import PlatformApple

/// Live `TimelineLoading` for one user's feed: wires the real `AuthorFeedService`
/// through a `LiveServiceContext`, fetches a page of `actor`'s posts (passing the
/// cursor for infinite scroll), persists any refreshed tokens, and maps the feed
/// into `PostDisplay` rows. `actor` is the user's DID.
struct LiveAuthorFeedLoader: TimelineLoading {
    let accountManager: AccountManager
    let config: OAuthClientConfig
    let actor: String

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku, actor: String) {
        self.accountManager = accountManager
        self.config = config
        self.actor = actor
    }

    func loadPage(cursor: String?) async throws -> TimelinePage {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = AuthorFeedService(
            sender: context.sender, metadataResolver: context.metadataResolver,
            config: context.config, refreshGate: context.refreshGate
        )

        let result = try await service.getAuthorFeed(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            actor: actor,
            cursor: cursor,
            filter: "posts_and_author_threads"
        )

        try context.persist(result.refreshed)

        let posts = result.response.feed.map(PostDisplay.init)
        return TimelinePage(posts: posts, cursor: result.response.cursor)
    }
}
