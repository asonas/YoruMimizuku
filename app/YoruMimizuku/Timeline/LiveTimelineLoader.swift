import Foundation
import os
import BlueskyCore
import YoruMimizukuKit

/// Live `TimelineLoading`: wires the real `TimelineService` through a
/// `LiveServiceContext`, fetches a page of the home timeline (passing the cursor
/// for infinite scroll), persists any refreshed tokens, and maps the feed into
/// `PostDisplay` rows.
struct LiveTimelineLoader: TimelineLoading {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    func loadPage(cursor: String?) async throws -> TimelinePage {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = TimelineService(
            sender: context.sender, metadataResolver: context.metadataResolver, config: context.config
        )

        let signposter = PerfSignpost.timeline
        let fetchInterval = signposter.beginInterval("Fetch timeline")
        let result = try await service.getTimeline(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            cursor: cursor
        )
        signposter.endInterval("Fetch timeline", fetchInterval, "\(result.response.feed.count) items")

        try context.persist(result.refreshed)

        let mapInterval = signposter.beginInterval("Map feed")
        let posts = result.response.feed.map(PostDisplay.init)
        signposter.endInterval("Map feed", mapInterval, "\(posts.count) posts")
        return TimelinePage(posts: posts, cursor: result.response.cursor)
    }
}
