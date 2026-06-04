import Foundation
import BlueskyCore
import HoshidukiyoKit

/// Live `NotificationsLoading`: wires the real `NotificationsService` through a
/// `LiveServiceContext`, fetches the latest notifications, persists any refreshed
/// tokens, and maps them into `NotificationDisplay` rows.
struct LiveNotificationsLoader: NotificationsLoading {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .hoshidukiyo) {
        self.accountManager = accountManager
        self.config = config
    }

    func loadLatest() async throws -> [NotificationDisplay] {
        let context = try LiveServiceContext(accountManager: accountManager, config: config)
        let service = NotificationsService(
            sender: context.sender, metadataResolver: context.metadataResolver, config: context.config
        )

        let result = try await service.listNotifications(
            pds: context.account.pds,
            issuer: context.issuer,
            accessToken: context.account.accessToken,
            refreshToken: context.account.refreshToken
        )

        try context.persist(result.refreshed)

        return result.response.notifications.map(NotificationDisplay.init)
    }
}
