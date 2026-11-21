import Foundation
import BlueskyCore

/// Fetches the signed-in account's profile via `ProfileService` so the sidebar can
/// show the real avatar instead of a placeholder. The avatar is cosmetic, so the
/// caller treats failures as "no avatar yet" rather than surfacing an error.
struct LiveProfileLoader {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    /// Resolve the avatar URL of the account `did` (a window's account), or nil
    /// when the profile has no avatar or the URL cannot be parsed. Throws when
    /// the account is no longer stored.
    func loadAvatar(of did: String) async throws -> URL? {
        let context = try LiveServiceContext(accountManager: accountManager, config: config, accountDID: did)
        let service = ProfileService(
            sender: context.sender, metadataResolver: context.metadataResolver, config: context.config, refreshGate: context.refreshGate
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
