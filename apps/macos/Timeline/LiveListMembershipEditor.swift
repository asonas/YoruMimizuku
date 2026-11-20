import Foundation
import BlueskyCore
import YoruMimizukuKit
import PlatformApple
import os

/// Live `ListMembershipEditing` for the window's account: reads its curated lists
/// with `app.bsky.graph.getListsWithMembership` and adds or removes people with
/// `app.bsky.graph.listitem` records. Lists are public records, so whoever is put
/// on one can see it.
struct LiveListMembershipEditor: ListMembershipEditing {
    let accountManager: AccountManager
    let accountDID: String
    var config: OAuthClientConfig = .yoruMimizuku

    private enum EditError: Error { case malformedItemURI(String) }
    private static let log = Logger(subsystem: "as.ason.YoruMimizuku", category: "ListMembership")

    func lists(withMembershipOf actorDID: String) async throws -> [CuratedListMembership] {
        do {
            return try await fetchLists(withMembershipOf: actorDID)
        } catch {
            Self.log.error("getListsWithMembership failed: \(Self.summary(of: error), privacy: .public)")
            throw error
        }
    }

    /// The parts of an error safe to log publicly: the HTTP status and the
    /// server's error name, never its message or a token response body.
    private static func summary(of error: Error) -> String {
        if case let XRPCError.requestFailed(status, body) = error {
            return "HTTP \(status) \(body?.error ?? "")"
        }
        return String(describing: type(of: error))
    }

    private func fetchLists(withMembershipOf actorDID: String) async throws -> [CuratedListMembership] {
        let context = try LiveServiceContext(accountManager: accountManager, config: config, accountDID: accountDID)
        let service = XRPCQueryService(
            sender: context.sender, metadataResolver: context.metadataResolver,
            config: context.config, refreshGate: context.refreshGate
        )
        // One page of up to 100 lists covers what a person curates by hand.
        let response: ListsWithMembershipResponse = try await service.query(
            "app.bsky.graph.getListsWithMembership",
            parameters: [("actor", actorDID), ("purposes", "curatelist"), ("limit", "100")],
            pds: context.account.pds, issuer: context.issuer,
            accessToken: context.account.accessToken, refreshToken: context.account.refreshToken,
            onRefresh: { try context.persist($0) }
        )
        return response.listsWithMembership
            .filter { $0.list.purpose == "app.bsky.graph.defs#curatelist" }
            .map { CuratedListMembership(listURI: $0.list.uri, name: $0.list.name, itemURI: $0.listItem?.uri) }
    }

    func add(actorDID: String, toList listURI: String) async throws -> String {
        let context = try LiveServiceContext(accountManager: accountManager, config: config, accountDID: accountDID)
        let result = try await postService(context).createRecord(
            pds: context.account.pds, issuer: context.issuer,
            accessToken: context.account.accessToken, refreshToken: context.account.refreshToken,
            repo: context.account.did, collection: "app.bsky.graph.listitem",
            record: ListItemRecordWrite(subject: actorDID, list: listURI, createdAt: PostService.timestamp())
        )
        try context.persist(result.refreshed)
        return result.response.uri
    }

    func remove(itemURI: String) async throws {
        guard let rkey = ATURI.rkey(itemURI) else { throw EditError.malformedItemURI(itemURI) }
        let context = try LiveServiceContext(accountManager: accountManager, config: config, accountDID: accountDID)
        let refreshed = try await postService(context).deleteRecord(
            pds: context.account.pds, issuer: context.issuer,
            accessToken: context.account.accessToken, refreshToken: context.account.refreshToken,
            repo: context.account.did, collection: "app.bsky.graph.listitem", rkey: rkey
        )
        try context.persist(refreshed)
    }

    private func postService(_ context: LiveServiceContext) -> PostService {
        PostService(sender: context.sender, metadataResolver: context.metadataResolver, config: context.config, refreshGate: context.refreshGate)
    }
}
