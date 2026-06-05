import Foundation
import os
import BlueskyCore
import YoruMimizukuKit
import PlatformApple

/// Live `TimelineLoading` for a saved filter. Holds the filter's expanded
/// subqueries: a single subquery (AND, or a one-term OR) is a plain `searchPosts`;
/// multiple subqueries (OR) are each searched with `sort=latest` and merged
/// newest-first, paginated through a `CompositeCursor`.
struct LiveSearchLoader: TimelineLoading {
    let accountManager: AccountManager
    let subqueries: [String]
    let config: OAuthClientConfig

    init(accountManager: AccountManager, subqueries: [String], config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.subqueries = subqueries
        self.config = config
    }

    func loadPage(cursor: String?) async throws -> TimelinePage {
        switch subqueries.count {
        case 0:
            return TimelinePage(posts: [], cursor: nil)
        case 1:
            let page = try await runQuery(subqueries[0], cursor: cursor)
            return TimelinePage(posts: page.posts, cursor: page.cursor)
        default:
            return try await loadComposite(cursor: cursor)
        }
    }

    /// Run one subquery and map to display rows, persisting any refreshed tokens.
    private func runQuery(_ query: String, cursor: String?) async throws -> (posts: [PostDisplay], cursor: String?) {
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
            cursor: cursor,
            sort: "latest"
        )
        try context.persist(result.refreshed)
        return (result.response.posts.map { PostDisplay(postView: $0) }, result.response.cursor)
    }

    /// OR: fetch each non-exhausted subquery, merge newest-first, and re-encode the
    /// per-subquery cursors. A failing subquery contributes no posts this page and
    /// keeps its cursor so a later page retries.
    private func loadComposite(cursor: String?) async throws -> TimelinePage {
        let decoded = CompositeCursor.decode(cursor)
        let isFirstPage = decoded == nil
        let composite = decoded ?? CompositeCursor(cursors: Array(repeating: nil, count: subqueries.count))

        var pages: [[PostDisplay]] = []
        var nextCursors: [String?] = []
        for (index, query) in subqueries.enumerated() {
            let sub = composite.cursors[index]
            // On follow-up pages a nil sub-cursor means that subquery is exhausted.
            if !isFirstPage && sub == nil {
                pages.append([])
                nextCursors.append(nil)
                continue
            }
            do {
                let page = try await runQuery(query, cursor: sub)
                pages.append(page.posts)
                nextCursors.append(page.cursor)
            } catch {
                pages.append([])
                nextCursors.append(sub)
            }
        }
        let merged = FilterSearchMerge.merge(pages)
        return TimelinePage(posts: merged, cursor: CompositeCursor(cursors: nextCursors).encoded())
    }
}
