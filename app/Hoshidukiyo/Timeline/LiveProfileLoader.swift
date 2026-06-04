import Foundation
import BlueskyCore

/// Fetches the signed-in account's profile via `ProfileService` so the sidebar can
/// show the real avatar instead of a placeholder. The avatar is cosmetic, so the
/// caller treats failures as "no avatar yet" rather than surfacing an error.
struct LiveProfileLoader {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .hoshidukiyo) {
        self.accountManager = accountManager
        self.config = config
    }

    /// Resolve the current account's avatar URL, or nil when there is no account,
    /// the profile has no avatar, or the URL cannot be parsed.
    func loadCurrentAvatar() async throws -> URL? {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = ProfileService(
            sender: context.sender, metadataResolver: context.metadataResolver, config: context.config
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
