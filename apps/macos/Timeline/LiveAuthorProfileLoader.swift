import Foundation
import BlueskyCore
import YoruMimizukuKit

/// Live `AuthorProfileLoading`: resolves a user's profile via the existing
/// `ProfileService` for the author tab header. Maps `ProfileViewBasic` into
/// `AuthorProfile`. The basic profile view carries no bio, so `bio` is nil for now;
/// the header renders display name, handle, and avatar regardless.
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
            sender: context.sender, metadataResolver: context.metadataResolver,
            config: context.config, refreshGate: context.refreshGate
        )

        let result = try await service.getProfile(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken,
            actor: actor
        )

        try context.persist(result.refreshed)

        let basic = result.response
        return AuthorProfile(
            did: basic.did,
            handle: basic.handle,
            displayName: basic.displayName,
            avatarURL: basic.avatar.flatMap(URL.init(string:)),
            bio: nil
        )
    }
}
