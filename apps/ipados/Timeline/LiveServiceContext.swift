import Crypto
import Foundation
import BlueskyCore

struct LiveServiceContext {
    let account: PersistedAccount
    let issuer: URL
    let sender: DPoPRequestSender
    let metadataResolver: OAuthMetadataResolver
    let config: OAuthClientConfig
    let refreshGate: RefreshGate
    private let accountManager: AccountManager

    enum ContextError: Error { case noCurrentAccount, invalidIssuer }

    init(accountManager: AccountManager, config: OAuthClientConfig) throws {
        guard let account = try accountManager.current() else {
            throw ContextError.noCurrentAccount
        }
        guard let issuer = URL(string: account.issuer) else {
            throw ContextError.invalidIssuer
        }

        let key = try P256.Signing.PrivateKey(rawRepresentation: account.dpopPrivateKeyRaw)
        let http = URLSessionHTTPClient()
        self.account = account
        self.issuer = issuer
        self.sender = DPoPRequestSender(
            http: http,
            proofBuilder: DPoPProofBuilder(crypto: CryptoKitDPoPProvider(privateKey: key))
        )
        self.metadataResolver = OAuthMetadataResolver(http: http)
        self.config = config
        self.refreshGate = accountManager.refreshGate
        self.accountManager = accountManager
    }

    func persist(_ refreshed: TokenResponse?) throws {
        guard let refreshed else { return }
        try accountManager.updateTokens(
            did: account.did,
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken ?? account.refreshToken,
            scope: refreshed.scope ?? account.scope
        )
    }
}
