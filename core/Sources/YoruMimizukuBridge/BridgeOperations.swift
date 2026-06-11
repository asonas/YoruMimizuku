#if canImport(WinSDK)
import Foundation
import Crypto
import BlueskyCore
import YoruMimizukuKit
import PlatformWindows

// MARK: - Output DTOs (JSON-friendly: URL -> String, Date -> ISO8601)

struct AccountDTO: Encodable {
    let did: String
    let handle: String?
    init(_ a: PersistedAccount) { did = a.did; handle = a.handle }
}

struct RichSegmentDTO: Encodable {
    let kind: String
    let text: String
    let url: String?
    init(_ s: RichTextSegment) {
        switch s.kind {
        case .text: kind = "text"
        case .link: kind = "link"
        case .tag: kind = "tag"
        case .mention: kind = "mention"
        }
        text = s.text
        url = s.url?.absoluteString
    }
}

struct PostImageDTO: Encodable {
    let thumbUrl: String?
    let fullsizeUrl: String?
    let alt: String
    init(_ i: PostImage) {
        thumbUrl = i.thumbURL?.absoluteString
        fullsizeUrl = i.fullsizeURL?.absoluteString
        alt = i.alt
    }
}

struct LinkCardDTO: Encodable {
    let url: String
    let title: String
    let description: String
    let thumbUrl: String?
    let host: String?
    init(_ c: LinkCard) {
        url = c.url.absoluteString
        title = c.title
        description = c.description
        thumbUrl = c.thumbURL?.absoluteString
        host = c.host
    }
}

struct PostDisplayDTO: Encodable {
    let id: String
    let cid: String
    let authorDisplayName: String
    let authorHandle: String
    let avatarUrl: String?
    let body: String
    let segments: [RichSegmentDTO]
    let createdAt: String
    let contextLabel: String?
    let images: [PostImageDTO]
    let linkCard: LinkCardDTO?
    let replyParent: ReplyParentDTO?
    let replyCount: Int
    let repostCount: Int
    let likeCount: Int
    let viewerLikeUri: String?
    let viewerRepostUri: String?
    let isLiked: Bool
    let isReposted: Bool

    init(_ p: PostDisplay) {
        id = p.id
        cid = p.cid
        authorDisplayName = p.authorDisplayName
        authorHandle = p.authorHandle
        avatarUrl = p.avatarURL?.absoluteString
        body = p.body
        segments = p.bodySegments.map(RichSegmentDTO.init)
        createdAt = ISO8601.string(p.createdAt)
        contextLabel = p.contextLabel
        images = p.images.map(PostImageDTO.init)
        linkCard = p.linkCard.map(LinkCardDTO.init)
        replyParent = p.replyParent.map { ReplyParentDTO($0.post) }
        replyCount = p.replyCount
        repostCount = p.repostCount
        likeCount = p.likeCount
        viewerLikeUri = p.viewerLikeURI
        viewerRepostUri = p.viewerRepostURI
        isLiked = p.isLiked
        isReposted = p.isReposted
    }
}

/// Single-level reply parent (avoids unbounded recursion in JSON).
struct ReplyParentDTO: Encodable {
    let id: String
    let authorDisplayName: String
    let authorHandle: String
    let avatarUrl: String?
    let body: String
    let segments: [RichSegmentDTO]
    init(_ p: PostDisplay) {
        id = p.id
        authorDisplayName = p.authorDisplayName
        authorHandle = p.authorHandle
        avatarUrl = p.avatarURL?.absoluteString
        body = p.body
        segments = p.bodySegments.map(RichSegmentDTO.init)
    }
}

struct TimelinePageDTO: Encodable {
    let posts: [PostDisplayDTO]
    let cursor: String?
}

struct NotificationActorDTO: Encodable {
    let displayName: String
    let handle: String
    let avatarUrl: String?
    init(_ a: NotificationGroup.Actor) {
        displayName = a.displayName; handle = a.handle; avatarUrl = a.avatarURL?.absoluteString
    }
}

struct NotificationGroupDTO: Encodable {
    let id: String
    let reason: String
    let actors: [NotificationActorDTO]
    let subjectUri: String?
    let subjectText: String?
    let subjectImageUrl: String?
    let text: String?
    let latestCreatedAt: String
    let isRead: Bool
    init(_ g: NotificationGroup) {
        id = g.id
        reason = Self.reasonString(g.reason)
        actors = g.actors.map(NotificationActorDTO.init)
        subjectUri = g.subjectURI
        subjectText = g.subjectText
        subjectImageUrl = g.subjectImageURL?.absoluteString
        text = g.text
        latestCreatedAt = ISO8601.string(g.latestCreatedAt)
        isRead = g.isRead
    }
    private static func reasonString(_ r: NotificationReason) -> String {
        switch r {
        case .like: return "like"
        case .repost: return "repost"
        case .follow: return "follow"
        case .mention: return "mention"
        case .reply: return "reply"
        case .quote: return "quote"
        case .other: return "other"
        }
    }
}

struct ProfileDTO: Encodable {
    let did: String
    let handle: String
    let displayName: String?
    let avatarUrl: String?
    let bio: String?

    init(_ p: ProfileViewBasic) {
        did = p.did
        handle = p.handle
        displayName = p.displayName
        avatarUrl = p.avatar
        bio = nil
    }
}

struct PostResultDTO: Encodable { let uri: String; let cid: String }
struct LoginBeginDTO: Encodable { let pendingId: String; let authUrl: String; let callbackScheme: String }
struct AvatarDTO: Encodable { let avatarUrl: String? }
struct RecordRefDTO: Encodable { let recordUri: String }
struct PermalinkDTO: Encodable { let url: String? }
struct EmptyDTO: Encodable { let done = true }

enum ISO8601 {
    static func string(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// Parse an ISO8601 timestamp produced by `string(_:)`, tolerating the
    /// fractional-seconds-less form too. Returns nil when neither matches.
    static func date(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: value) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

// MARK: - Operations

enum BridgeOps {
    // -- Account --

    static func accountCurrent() throws -> AccountDTO? {
        let rt = try BridgeRuntime.require()
        return try rt.accountManager.current().map(AccountDTO.init)
    }

    static func accountList() throws -> [String] {
        try BridgeRuntime.require().accountManager.allDIDs()
    }

    static func accountSwitch(did: String) throws -> EmptyDTO {
        try BridgeRuntime.require().accountManager.switchTo(did: did); return EmptyDTO()
    }

    static func accountRemove(did: String) throws -> EmptyDTO {
        try BridgeRuntime.require().accountManager.remove(did: did); return EmptyDTO()
    }

    // -- Login (split for WebView2) --

    static func loginBegin(handle: String) async throws -> LoginBeginDTO {
        let rt = try BridgeRuntime.require()
        let dpopKey = P256.Signing.PrivateKey()
        let crypto = CryptoKitDPoPProvider(privateKey: dpopKey)
        let http = URLSessionHTTPClient()
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: crypto))

        let discovered = try await OAuthDiscovery(http: http).discover(account: handle)
        let random = BCryptRandomBytesGenerator()
        let verifier = PKCE.generateVerifier(randomBytes: random.bytes)
        let pkce = PKCE.make(verifier: verifier, sha256: { crypto.sha256($0) })
        let state = AuthorizationRequest.generateState(randomBytes: random.bytes)
        let request = AuthorizationRequest(config: rt.config, pkce: pkce, state: state, loginHint: handle)
        let par = try await AuthorizationRequestService(sender: sender)
            .push(metadata: discovered.metadata, request: request)
        let authURL = try AuthorizationRequestService.authorizationURL(
            metadata: discovered.metadata, config: rt.config, requestURI: par.requestURI
        )

        let id = UUID().uuidString
        rt.putPending(id, PendingLogin(
            handle: handle, verifier: verifier, state: state,
            dpopPrivateKeyRaw: dpopKey.rawRepresentation, discovered: discovered
        ))
        return LoginBeginDTO(pendingId: id, authUrl: authURL.absoluteString, callbackScheme: rt.config.callbackScheme)
    }

    static func loginComplete(pendingId: String, callbackUrl: String) async throws -> AccountDTO {
        let rt = try BridgeRuntime.require()
        guard let pending = rt.takePending(pendingId) else { throw BridgeError.unknownPendingLogin }
        guard let url = URL(string: callbackUrl) else { throw BridgeError.message("invalid callback URL") }
        let callback = try OAuthCallback.parse(url: url)
        guard callback.state == pending.state else { throw OAuthError.stateMismatch }

        let key = try P256.Signing.PrivateKey(rawRepresentation: pending.dpopPrivateKeyRaw)
        let crypto = CryptoKitDPoPProvider(privateKey: key)
        let http = URLSessionHTTPClient()
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: crypto))
        let tokens = try await TokenService(sender: sender).requestToken(
            metadata: pending.discovered.metadata, config: rt.config,
            grant: .authorizationCode(code: callback.code, codeVerifier: pending.verifier)
        )
        let result = OAuthLoginResult(
            did: tokens.sub, pds: pending.discovered.pds,
            authorizationServerIssuer: pending.discovered.authorizationServerIssuer, tokens: tokens
        )
        let account = try rt.accountManager.add(
            loginResult: result, handle: pending.handle, dpopPrivateKeyRaw: pending.dpopPrivateKeyRaw
        )
        return AccountDTO(account)
    }

    // -- Feeds --

    static func timelineLoad(cursor: String?) async throws -> TimelinePageDTO {
        let rt = try BridgeRuntime.require()
        let ctx = try BridgeServiceContext(accountManager: rt.accountManager, config: rt.config)
        let service = TimelineService(sender: ctx.sender, metadataResolver: ctx.metadataResolver, config: ctx.config)
        let result = try await service.getTimeline(
            pds: ctx.account.pds, issuer: ctx.issuer,
            accessToken: ctx.account.accessToken, refreshToken: ctx.account.refreshToken, cursor: cursor
        )
        try ctx.persist(result.refreshed)
        return TimelinePageDTO(
            posts: result.response.feed.map { PostDisplayDTO(PostDisplay($0)) },
            cursor: result.response.cursor
        )
    }

    static func authorFeedLoad(actor: String, cursor: String?) async throws -> TimelinePageDTO {
        let rt = try BridgeRuntime.require()
        let ctx = try BridgeServiceContext(accountManager: rt.accountManager, config: rt.config)
        let service = AuthorFeedService(sender: ctx.sender, metadataResolver: ctx.metadataResolver, config: ctx.config)
        let result = try await service.getAuthorFeed(
            pds: ctx.account.pds, issuer: ctx.issuer,
            accessToken: ctx.account.accessToken, refreshToken: ctx.account.refreshToken,
            actor: actor, cursor: cursor, filter: "posts_and_author_threads"
        )
        try ctx.persist(result.refreshed)
        return TimelinePageDTO(
            posts: result.response.feed.map { PostDisplayDTO(PostDisplay($0)) },
            cursor: result.response.cursor
        )
    }

    static func threadLoad(uri: String) async throws -> PostDisplayDTO {
        let rt = try BridgeRuntime.require()
        let ctx = try BridgeServiceContext(accountManager: rt.accountManager, config: rt.config)
        let service = ThreadService(sender: ctx.sender, metadataResolver: ctx.metadataResolver, config: ctx.config)
        let result = try await service.getPostThread(
            pds: ctx.account.pds, issuer: ctx.issuer,
            accessToken: ctx.account.accessToken, refreshToken: ctx.account.refreshToken, uri: uri
        )
        try ctx.persist(result.refreshed)
        return PostDisplayDTO(PostDisplay(result.response.thread))
    }

    static func notificationsLoad() async throws -> [NotificationGroupDTO] {
        let rt = try BridgeRuntime.require()
        let ctx = try BridgeServiceContext(accountManager: rt.accountManager, config: rt.config)
        let service = NotificationsService(sender: ctx.sender, metadataResolver: ctx.metadataResolver, config: ctx.config)
        let result = try await service.listNotifications(
            pds: ctx.account.pds, issuer: ctx.issuer,
            accessToken: ctx.account.accessToken, refreshToken: ctx.account.refreshToken
        )
        try ctx.persist(result.refreshed)
        let groups = NotificationGroup.group(result.response.notifications.map(NotificationDisplay.init))
        let subjects = try await resolveSubjects(for: groups, runtime: rt)
        return groups.map { group -> NotificationGroupDTO in
            guard let uri = group.subjectURI, let post = subjects[uri] else { return NotificationGroupDTO(group) }
            let resolved = group.withSubject(
                text: post.record.text,
                imageURL: post.embed?.images.first.flatMap { URL(string: $0.thumb) }
            )
            return NotificationGroupDTO(resolved)
        }
    }

    private static func resolveSubjects(
        for groups: [NotificationGroup], runtime rt: BridgeRuntime
    ) async throws -> [String: PostView] {
        let uris = groups.filter { $0.reason == .like || $0.reason == .repost }.compactMap(\.subjectURI)
        var unique: [String] = []
        var seen = Set<String>()
        for uri in uris where seen.insert(uri).inserted { unique.append(uri) }
        guard !unique.isEmpty else { return [:] }

        let ctx = try BridgeServiceContext(accountManager: rt.accountManager, config: rt.config)
        let service = PostsService(sender: ctx.sender, metadataResolver: ctx.metadataResolver, config: ctx.config)
        var posts: [String: PostView] = [:]
        var accessToken = ctx.account.accessToken
        for batch in unique.chunked(into: PostsService.maxURIsPerRequest) {
            let result = try await service.getPosts(
                pds: ctx.account.pds, issuer: ctx.issuer,
                accessToken: accessToken, refreshToken: ctx.account.refreshToken, uris: batch
            )
            try ctx.persist(result.refreshed)
            if let refreshed = result.refreshed { accessToken = refreshed.accessToken }
            for post in result.response.posts { posts[post.uri] = post }
        }
        return posts
    }

    // -- Search / filters --

    static func searchLoad(filter: SavedFilter, cursor: String?) async throws -> TimelinePageDTO {
        let rt = try BridgeRuntime.require()
        let ctx = try BridgeServiceContext(accountManager: rt.accountManager, config: rt.config)
        let service = SearchService(sender: ctx.sender, metadataResolver: ctx.metadataResolver, config: ctx.config)
        let queries = filter.subqueries
        guard !queries.isEmpty else { return TimelinePageDTO(posts: [], cursor: nil) }

        if queries.count == 1 {
            let result = try await service.searchPosts(
                pds: ctx.account.pds, issuer: ctx.issuer,
                accessToken: ctx.account.accessToken, refreshToken: ctx.account.refreshToken,
                query: queries[0], cursor: cursor, sort: "latest"
            )
            try ctx.persist(result.refreshed)
            return TimelinePageDTO(
                posts: result.response.posts.map { PostDisplayDTO(PostDisplay(postView: $0)) },
                cursor: result.response.cursor
            )
        }

        let decoded = CompositeCursor.decode(cursor)
        let isFirstPage = decoded == nil
        let composite = decoded ?? CompositeCursor(cursors: Array(repeating: nil, count: queries.count))
        let cursors = composite.cursors.count == queries.count
            ? composite.cursors
            : Array(repeating: nil, count: queries.count)

        var pages: [[PostDisplay]] = []
        var nextCursors: [String?] = []
        var accessToken = ctx.account.accessToken
        for (index, query) in queries.enumerated() {
            let subCursor = cursors[index]
            if !isFirstPage && subCursor == nil {
                pages.append([])
                nextCursors.append(nil)
                continue
            }
            let result = try await service.searchPosts(
                pds: ctx.account.pds, issuer: ctx.issuer,
                accessToken: accessToken, refreshToken: ctx.account.refreshToken,
                query: query, cursor: subCursor, sort: "latest"
            )
            try ctx.persist(result.refreshed)
            if let refreshed = result.refreshed { accessToken = refreshed.accessToken }
            pages.append(result.response.posts.map { PostDisplay(postView: $0) })
            nextCursors.append(result.response.cursor)
        }
        let merged = FilterSearchMerge.merge(pages)
        return TimelinePageDTO(
            posts: merged.map(PostDisplayDTO.init),
            cursor: CompositeCursor(cursors: nextCursors).encoded()
        )
    }

    // -- Compose --

    static func postCreate(_ draft: PostDraft) async throws -> PostResultDTO {
        let rt = try BridgeRuntime.require()
        let ctx = try BridgeServiceContext(accountManager: rt.accountManager, config: rt.config)
        let service = PostService(sender: ctx.sender, metadataResolver: ctx.metadataResolver, config: ctx.config)
        let images = draft.images.map { (data: $0.data, mimeType: $0.mimeType, alt: $0.alt) }
        let result = try await service.createPost(
            pds: ctx.account.pds, issuer: ctx.issuer,
            accessToken: ctx.account.accessToken, refreshToken: ctx.account.refreshToken,
            did: ctx.account.did, text: draft.text, images: images,
            replyParentURI: draft.replyParentURI, quote: draft.quote
        )
        try ctx.persist(result.refreshed)
        return PostResultDTO(uri: result.response.uri, cid: result.response.cid)
    }

    // -- Interactions --

    static func like(uri: String, cid: String) async throws -> RecordRefDTO {
        let rt = try BridgeRuntime.require()
        let ctx = try BridgeServiceContext(accountManager: rt.accountManager, config: rt.config)
        let service = PostService(sender: ctx.sender, metadataResolver: ctx.metadataResolver, config: ctx.config)
        let result = try await service.like(
            pds: ctx.account.pds, issuer: ctx.issuer,
            accessToken: ctx.account.accessToken, refreshToken: ctx.account.refreshToken,
            repo: ctx.account.did, subject: StrongRef(uri: uri, cid: cid)
        )
        try ctx.persist(result.refreshed)
        return RecordRefDTO(recordUri: result.response.uri)
    }

    static func repost(uri: String, cid: String) async throws -> RecordRefDTO {
        let rt = try BridgeRuntime.require()
        let ctx = try BridgeServiceContext(accountManager: rt.accountManager, config: rt.config)
        let service = PostService(sender: ctx.sender, metadataResolver: ctx.metadataResolver, config: ctx.config)
        let result = try await service.repost(
            pds: ctx.account.pds, issuer: ctx.issuer,
            accessToken: ctx.account.accessToken, refreshToken: ctx.account.refreshToken,
            repo: ctx.account.did, subject: StrongRef(uri: uri, cid: cid)
        )
        try ctx.persist(result.refreshed)
        return RecordRefDTO(recordUri: result.response.uri)
    }

    static func removeRecord(recordUri: String, collection: String) async throws -> EmptyDTO {
        guard let rkey = ATURI.rkey(recordUri) else { throw BridgeError.message("malformed record URI") }
        let rt = try BridgeRuntime.require()
        let ctx = try BridgeServiceContext(accountManager: rt.accountManager, config: rt.config)
        let service = PostService(sender: ctx.sender, metadataResolver: ctx.metadataResolver, config: ctx.config)
        let refreshed = try await service.deleteRecord(
            pds: ctx.account.pds, issuer: ctx.issuer,
            accessToken: ctx.account.accessToken, refreshToken: ctx.account.refreshToken,
            repo: ctx.account.did, collection: collection, rkey: rkey
        )
        try ctx.persist(refreshed)
        return EmptyDTO()
    }

    static func permalink(id: String, authorHandle: String) throws -> PermalinkDTO {
        PermalinkDTO(url: PostPermalink.url(id: id, authorHandle: authorHandle)?.absoluteString)
    }

    // -- Profile --

    static func avatar() async throws -> AvatarDTO {
        let rt = try BridgeRuntime.require()
        let ctx = try BridgeServiceContext(accountManager: rt.accountManager, config: rt.config)
        let service = ProfileService(sender: ctx.sender, metadataResolver: ctx.metadataResolver, config: ctx.config)
        let result = try await service.getProfile(
            pds: ctx.account.pds, issuer: ctx.issuer,
            accessToken: ctx.account.accessToken, refreshToken: ctx.account.refreshToken, actor: ctx.account.did
        )
        try ctx.persist(result.refreshed)
        return AvatarDTO(avatarUrl: result.response.avatar)
    }

    static func profile(actor: String) async throws -> ProfileDTO {
        let rt = try BridgeRuntime.require()
        let ctx = try BridgeServiceContext(accountManager: rt.accountManager, config: rt.config)
        let service = ProfileService(sender: ctx.sender, metadataResolver: ctx.metadataResolver, config: ctx.config)
        let result = try await service.getProfile(
            pds: ctx.account.pds, issuer: ctx.issuer,
            accessToken: ctx.account.accessToken, refreshToken: ctx.account.refreshToken, actor: actor
        )
        try ctx.persist(result.refreshed)
        return ProfileDTO(result.response)
    }

    // -- Link previews (OGP) --

    /// Fetch an OGP preview card for a bare URL, mirroring the macOS client-side
    /// fallback. Returns nil when the URL is unparseable or yields no usable
    /// metadata; results (and misses) are cached process-wide per URL.
    static func ogpLoad(url: String) async -> LinkCardDTO? {
        guard let parsed = URL(string: url) else { return nil }
        return await BridgeLinkPreviews.shared.preview(for: parsed).map(LinkCardDTO.init)
    }

    // -- Feed thread grouping (web-style) --

    /// One post reduced to just what `FeedThreading.arrange` needs: its id, its
    /// creation time, and the id of its reply parent when that parent is also on
    /// the page. The C# feed sends this for the loaded page and reorders its rows
    /// from the result, keeping the grouping logic in the tested core.
    struct ArrangeItem: Decodable, Sendable {
        let id: String
        let createdAt: String
        let replyParentId: String?
    }

    struct ArrangeResultDTO: Encodable {
        let id: String
        let connectsToPrevious: Bool
        let connectsToNext: Bool
    }

    static func feedArrange(items: [ArrangeItem]) -> [ArrangeResultDTO] {
        let posts: [PostDisplay] = items.map { item in
            let created = ISO8601.date(item.createdAt) ?? Date(timeIntervalSince1970: 0)
            let parent = item.replyParentId.map { parentID in
                ReplyParent(PostDisplay(
                    id: parentID, authorDisplayName: "", authorHandle: "", body: "", createdAt: created
                ))
            }
            return PostDisplay(
                id: item.id, authorDisplayName: "", authorHandle: "", body: "",
                createdAt: created, replyParent: parent
            )
        }
        return FeedThreading.arrange(posts).map {
            ArrangeResultDTO(
                id: $0.post.id,
                connectsToPrevious: $0.connectsToPrevious,
                connectsToNext: $0.connectsToNext
            )
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
#endif
