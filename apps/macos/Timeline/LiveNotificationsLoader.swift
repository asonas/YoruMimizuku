import Foundation
import BlueskyCore
import YoruMimizukuKit

/// Live `NotificationsLoading`: wires the real `NotificationsService` through a
/// `LiveServiceContext`, fetches the latest notifications, groups them, then
/// resolves the target post of each like/repost group via `app.bsky.feed.getPosts`
/// so the UI can show which post a reaction was about. Persists any refreshed
/// tokens along the way.
struct LiveNotificationsLoader: NotificationsLoading {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    func loadLatest() async throws -> [NotificationGroup] {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = NotificationsService(
            sender: context.sender, metadataResolver: context.metadataResolver, config: context.config, refreshGate: context.refreshGate
        )

        let result = try await service.listNotifications(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken
        )
        try context.persist(result.refreshed)

        let groups = NotificationGroup.group(result.response.notifications.map(NotificationDisplay.init))
        let subjects = try await resolveSubjects(for: groups)
        return groups.map { group in
            guard let uri = group.subjectURI, let post = subjects[uri] else { return group }
            return group.withSubject(text: post.record.text, imageURL: post.embed?.images.first.flatMap { URL(string: $0.thumb) })
        }
    }

    /// Fetch the target posts for like/repost groups, returning a `uri -> PostView`
    /// map. URIs are deduplicated and batched to respect `getPosts`'s 25-URI cap.
    private func resolveSubjects(for groups: [NotificationGroup]) async throws -> [String: PostView] {
        let uris = groups
            .filter { $0.reason == .like || $0.reason == .repost }
            .compactMap(\.subjectURI)
        var unique: [String] = []
        var seen = Set<String>()
        for uri in uris where seen.insert(uri).inserted { unique.append(uri) }
        guard !unique.isEmpty else { return [:] }

        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = PostsService(
            sender: context.sender, metadataResolver: context.metadataResolver, config: context.config, refreshGate: context.refreshGate
        )

        var posts: [String: PostView] = [:]
        var accessToken = context.account.accessToken
        for batch in unique.chunked(into: PostsService.maxURIsPerRequest) {
            let result = try await service.getPosts(
                pds: context.account.pds,
                issuer: context.issuer,
                accessToken: accessToken,
                refreshToken: context.account.refreshToken,
                uris: batch
            )
            try context.persist(result.refreshed)
            if let refreshed = result.refreshed { accessToken = refreshed.accessToken }
            for post in result.response.posts { posts[post.uri] = post }
        }
        return posts
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
