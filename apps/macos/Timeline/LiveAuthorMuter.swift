import Foundation
import BlueskyCore
import PlatformApple

/// Mutes an account for the window's account (`app.bsky.graph.muteActor`).
/// Mutes are private to the viewer.
struct LiveAuthorMuter {
    let accountManager: AccountManager
    let accountDID: String
    var config: OAuthClientConfig = .yoruMimizuku

    func mute(_ actorDID: String) async throws {
        let context = try LiveServiceContext(accountManager: accountManager, config: config, accountDID: accountDID)
        let service = PostService(
            sender: context.sender, metadataResolver: context.metadataResolver,
            config: context.config, refreshGate: context.refreshGate
        )
        let refreshed = try await service.muteActor(
            pds: context.account.pds, issuer: context.issuer,
            accessToken: context.account.accessToken, refreshToken: context.account.refreshToken,
            actor: actorDID
        )
        try context.persist(refreshed)
    }
}
