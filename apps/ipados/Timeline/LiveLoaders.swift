import Foundation
import BlueskyCore
import YoruMimizukuKit

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
            sender: context.sender,
            metadataResolver: context.metadataResolver,
            config: context.config,
            refreshGate: context.refreshGate
        )
        let result = try await service.getTimeline(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            cursor: cursor
        )
        try context.persist(result.refreshed)
        return TimelinePage(posts: result.response.feed.map(PostDisplay.init), cursor: result.response.cursor)
    }
}

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
            sender: context.sender,
            metadataResolver: context.metadataResolver,
            config: context.config,
            refreshGate: context.refreshGate
        )
        let result = try await service.listNotifications(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken
        )
        try context.persist(result.refreshed)
        return NotificationGroup.group(result.response.notifications.map(NotificationDisplay.init))
    }
}

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
        guard let query = subqueries.first else { return TimelinePage(posts: [], cursor: nil) }
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = SearchService(
            sender: context.sender,
            metadataResolver: context.metadataResolver,
            config: context.config,
            refreshGate: context.refreshGate
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
        return TimelinePage(posts: result.response.posts.map { PostDisplay(postView: $0) }, cursor: result.response.cursor)
    }
}

struct LiveThreadLoader: ThreadLoading {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    func loadThread(uri: String) async throws -> ConversationThread {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = ThreadService(
            sender: context.sender,
            metadataResolver: context.metadataResolver,
            config: context.config,
            refreshGate: context.refreshGate
        )
        let result = try await service.getPostThread(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            uri: uri
        )
        try context.persist(result.refreshed)
        let thread = result.response.thread
        return ConversationThread(focus: PostDisplay(thread), replies: ThreadNode.childTree(of: thread, maxDepth: 3))
    }
}

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
            sender: context.sender,
            metadataResolver: context.metadataResolver,
            config: context.config,
            refreshGate: context.refreshGate
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
        return TimelinePage(posts: result.response.feed.map(PostDisplay.init), cursor: result.response.cursor)
    }
}

struct LiveAuthorProfileLoader: AuthorProfileLoading {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    func loadProfile(actor: String) async throws -> AuthorProfile {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = ProfileService(
            sender: context.sender,
            metadataResolver: context.metadataResolver,
            config: context.config,
            refreshGate: context.refreshGate
        )
        let result = try await service.getProfile(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            actor: actor
        )
        try context.persist(result.refreshed)
        let profile = result.response
        return AuthorProfile(
            did: profile.did,
            handle: profile.handle,
            displayName: profile.displayName,
            avatarURL: profile.avatar.flatMap(URL.init(string:)),
            bio: nil
        )
    }
}

struct LiveProfileLoader {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    func loadCurrentAvatar() async throws -> URL? {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = ProfileService(
            sender: context.sender,
            metadataResolver: context.metadataResolver,
            config: context.config,
            refreshGate: context.refreshGate
        )
        let result = try await service.getProfile(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            actor: context.account.did
        )
        try context.persist(result.refreshed)
        return result.response.avatar.flatMap(URL.init(string:))
    }
}
