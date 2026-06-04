import Foundation
import CryptoKit
import BlueskyCore
import HoshidukiyoKit

/// Live `ThreadLoading`: restores the current account's DPoP key, wires the real
/// `ThreadService`, fetches a post's thread, persists any refreshed tokens, and
/// maps the focused post (with its immediate parent) into a `PostDisplay`.
struct LiveThreadLoader: ThreadLoading {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .hoshidukiyo) {
        self.accountManager = accountManager
        self.config = config
    }

    enum LoaderError: Error { case noCurrentAccount, invalidIssuer }

    func loadThread(uri: String) async throws -> PostDisplay {
        guard let account = try accountManager.current() else {
            throw LoaderError.noCurrentAccount
        }
        guard let issuer = URL(string: account.issuer) else {
            throw LoaderError.invalidIssuer
        }

        let key = try P256.Signing.PrivateKey(rawRepresentation: account.dpopPrivateKeyRaw)
        let crypto = CryptoKitDPoPProvider(privateKey: key)
        let http = URLSessionHTTPClient()
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: crypto))
        let service = ThreadService(
            sender: sender, metadataResolver: OAuthMetadataResolver(http: http), config: config
        )

        let result = try await service.getPostThread(
            pds: account.pds,
            issuer: issuer,
            accessToken: account.accessToken,
            refreshToken: account.refreshToken,
            uri: uri
        )

        if let refreshed = result.refreshed {
            try accountManager.updateTokens(
                did: account.did,
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken ?? account.refreshToken,
                scope: refreshed.scope ?? account.scope
            )
        }

        return PostDisplay(result.response.thread)
    }
}
