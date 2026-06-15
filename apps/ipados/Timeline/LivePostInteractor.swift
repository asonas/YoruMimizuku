import Foundation
import BlueskyCore
import YoruMimizukuKit

struct LivePostInteractor: PostInteracting {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    private enum InteractionError: Error { case malformedRecordURI(String) }

    func like(uri: String, cid: String) async throws -> String {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let result = try await service(context).like(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            repo: context.account.did,
            subject: StrongRef(uri: uri, cid: cid)
        )
        try context.persist(result.refreshed)
        return result.response.uri
    }

    func repost(uri: String, cid: String) async throws -> String {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let result = try await service(context).repost(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            repo: context.account.did,
            subject: StrongRef(uri: uri, cid: cid)
        )
        try context.persist(result.refreshed)
        return result.response.uri
    }

    func removeLike(recordURI: String) async throws {
        try await delete(recordURI: recordURI, collection: "app.bsky.feed.like")
    }

    func removeRepost(recordURI: String) async throws {
        try await delete(recordURI: recordURI, collection: "app.bsky.feed.repost")
    }

    func deletePost(uri: String) async throws {
        try await delete(recordURI: uri, collection: "app.bsky.feed.post")
    }

    private func delete(recordURI: String, collection: String) async throws {
        guard let rkey = ATURI.rkey(recordURI) else {
            throw InteractionError.malformedRecordURI(recordURI)
        }
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let refreshed = try await service(context).deleteRecord(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            repo: context.account.did,
            collection: collection,
            rkey: rkey
        )
        try context.persist(refreshed)
    }

    private func service(_ context: LiveServiceContext) -> PostService {
        PostService(
            sender: context.sender,
            metadataResolver: context.metadataResolver,
            config: context.config,
            refreshGate: context.refreshGate
        )
    }
}
