import Foundation
import BlueskyCore
import YoruMimizukuKit
import PlatformApple

/// Runs one XRPC query as the window's account and persists refreshed tokens.
private func query<Response: Decodable>(
    _ nsid: String,
    _ parameters: [(String, String)],
    accountManager: AccountManager,
    accountDID: String,
    config: OAuthClientConfig
) async throws -> Response {
    let context = try LiveServiceContext(accountManager: accountManager, config: config, accountDID: accountDID)
    let service = XRPCQueryService(
        sender: context.sender, metadataResolver: context.metadataResolver,
        config: context.config, refreshGate: context.refreshGate
    )
    return try await service.query(
        nsid, parameters: parameters,
        pds: context.account.pds, issuer: context.issuer,
        accessToken: context.account.accessToken, refreshToken: context.account.refreshToken,
        onRefresh: { try context.persist($0) }
    )
}

/// Live `SavedFeedsLoading`: reads the account's pins (`getPreferences`), then
/// the names of the pinned feeds (`getFeedGenerators`, one request) and lists
/// (`getList`, one request each).
struct LiveSavedFeedsLoader: SavedFeedsLoading {
    let accountManager: AccountManager
    let accountDID: String
    var config: OAuthClientConfig = .yoruMimizuku

    func loadPinned() async throws -> [SavedFeedSource] {
        let preferences: PreferencesResponse = try await query(
            "app.bsky.actor.getPreferences", [], accountManager: accountManager, accountDID: accountDID, config: config
        )
        let pinned = preferences.savedFeeds.filter(\.pinned)

        let feedURIs = Array(Set(pinned.filter { $0.type == "feed" }.map(\.value)))
        var feeds: [FeedGeneratorView] = []
        if !feedURIs.isEmpty {
            let response: FeedGeneratorsResponse = try await query(
                "app.bsky.feed.getFeedGenerators", feedURIs.map { ("feeds", $0) },
                accountManager: accountManager, accountDID: accountDID, config: config
            )
            feeds = response.feeds
        }

        var lists: [ListView] = []
        for uri in Set(pinned.filter { $0.type == "list" }.map(\.value)) {
            do {
                let response: ListResponse = try await query(
                    "app.bsky.graph.getList", [("list", uri), ("limit", "1")],
                    accountManager: accountManager, accountDID: accountDID, config: config
                )
                lists.append(response.list)
            } catch let XRPCError.requestFailed(status: 400, body) where body?.error == "InvalidRequest" {
                // The appview answers InvalidRequest for a list it cannot resolve
                // (deleted or blocked); skip it. Any other failure, including other
                // 400s such as a DPoP nonce error, aborts the load so the sidebar
                // keeps the pins it already shows.
            }
        }

        return SavedFeedSource.pinned(from: pinned, feeds: feeds, lists: lists)
    }
}

/// Live `TimelineLoading` for a pinned feed (`app.bsky.feed.getFeed`) or list
/// (`app.bsky.feed.getListFeed`). Both answer in the `getTimeline` shape.
struct LiveSavedFeedLoader: TimelineLoading {
    let accountManager: AccountManager
    let accountDID: String
    let source: SavedFeedSource
    var config: OAuthClientConfig = .yoruMimizuku

    func loadPage(cursor: String?) async throws -> TimelinePage {
        let nsid: String
        var parameters: [(String, String)]
        switch source.kind {
        case .feed:
            nsid = "app.bsky.feed.getFeed"
            parameters = [("feed", source.id)]
        case .list:
            nsid = "app.bsky.feed.getListFeed"
            parameters = [("list", source.id)]
        }
        parameters.append(("limit", "50"))
        if let cursor { parameters.append(("cursor", cursor)) }

        let response: TimelineResponse = try await query(
            nsid, parameters, accountManager: accountManager, accountDID: accountDID, config: config
        )
        return TimelinePage(posts: response.feed.map(PostDisplay.init), cursor: response.cursor)
    }
}
