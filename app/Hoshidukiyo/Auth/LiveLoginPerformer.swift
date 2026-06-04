import Foundation
import CryptoKit
import BlueskyCore
import HoshidukiyoKit

/// Live `LoginPerforming`: generates a fresh DPoP P-256 key, wires the real
/// `OAuthClient` collaborators, runs the OAuth login, and persists the account
/// (with the DPoP key) via `AccountManager`. Returns the account DID.
struct LiveLoginPerformer: LoginPerforming {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .hoshidukiyo) {
        self.accountManager = accountManager
        self.config = config
    }

    func login(handle: String) async throws -> String {
        // One DPoP key for this account, used during login and persisted for reuse.
        let dpopKey = P256.Signing.PrivateKey()
        let crypto = CryptoKitDPoPProvider(privateKey: dpopKey)

        let http = URLSessionHTTPClient()
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: crypto))

        // ASWebAuthBrowserSession is main-actor-isolated (it conforms to the
        // main-actor ASWebAuthenticationPresentationContextProviding protocol),
        // so construct it on the main actor before wiring the client.
        let browser = await MainActor.run { ASWebAuthBrowserSession() }

        let client = OAuthClient(
            discovery: OAuthDiscovery(http: http),
            authorizationRequester: AuthorizationRequestService(sender: sender),
            tokenRequester: TokenService(sender: sender),
            browser: browser,
            random: SecRandomBytesGenerator(),
            sha256: { crypto.sha256($0) },
            config: config
        )

        let result = try await client.login(account: handle)
        let account = try accountManager.add(
            loginResult: result,
            handle: handle,
            dpopPrivateKeyRaw: dpopKey.rawRepresentation
        )
        return account.did
    }
}
