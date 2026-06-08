import Crypto
import Foundation
import BlueskyCore
import PlatformApple
import YoruMimizukuKit

struct LiveLoginPerformer: LoginPerforming {
    let accountManager: AccountManager
    let config: OAuthClientConfig

    init(accountManager: AccountManager, config: OAuthClientConfig = .yoruMimizuku) {
        self.accountManager = accountManager
        self.config = config
    }

    func login(handle: String) async throws -> String {
        let dpopKey = P256.Signing.PrivateKey()
        let crypto = CryptoKitDPoPProvider(privateKey: dpopKey)
        let http = URLSessionHTTPClient()
        let sender = DPoPRequestSender(http: http, proofBuilder: DPoPProofBuilder(crypto: crypto))
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
