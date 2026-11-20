import Foundation
import BlueskyCore
import PlatformApple

/// Reads one record exactly as stored in its repo (`com.atproto.repo.getRecord`),
/// for the detail pane's レコード tab.
struct LiveRecordLoader {
    let accountManager: AccountManager
    let accountDID: String
    var config: OAuthClientConfig = .yoruMimizuku

    private enum LoadError: Error { case malformedURI(String) }

    func load(_ uri: String) async throws -> RecordResponse {
        // at://<repo>/<collection>/<rkey>
        let parts = uri.replacingOccurrences(of: "at://", with: "").split(separator: "/").map(String.init)
        guard parts.count == 3 else { throw LoadError.malformedURI(uri) }
        let context = try LiveServiceContext(accountManager: accountManager, config: config, accountDID: accountDID)
        let service = XRPCQueryService(
            sender: context.sender, metadataResolver: context.metadataResolver,
            config: context.config, refreshGate: context.refreshGate
        )
        return try await service.query(
            "com.atproto.repo.getRecord",
            parameters: [("repo", parts[0]), ("collection", parts[1]), ("rkey", parts[2])],
            pds: context.account.pds, issuer: context.issuer,
            accessToken: context.account.accessToken, refreshToken: context.account.refreshToken,
            onRefresh: { try context.persist($0) }
        )
    }
}
