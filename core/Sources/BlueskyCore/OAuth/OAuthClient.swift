import Foundation

/// The result of a successful OAuth login: the account DID (authoritative `sub`
/// from the token response), its PDS, the authorization server issuer, and the
/// issued tokens. The platform layer persists these.
public struct OAuthLoginResult: Equatable, Sendable {
    public let did: String
    public let pds: URL
    public let authorizationServerIssuer: String
    public let tokens: TokenResponse

    /// Public so an out-of-module orchestrator (e.g. the Windows C ABI bridge,
    /// which drives the OAuth steps itself for the WebView2 split flow) can build
    /// the result from a token exchange.
    public init(did: String, pds: URL, authorizationServerIssuer: String, tokens: TokenResponse) {
        self.did = did
        self.pds = pds
        self.authorizationServerIssuer = authorizationServerIssuer
        self.tokens = tokens
    }
}

/// Orchestrates the full atproto OAuth login: discovery → PKCE/state → PAR →
/// authorization URL → browser approval → callback parsing + state check →
/// token exchange. All collaborators are injected so the whole flow is testable
/// with fakes.
public struct OAuthClient: Sendable {
    private let discovery: AccountDiscovering
    private let authorizationRequester: AuthorizationRequesting
    private let tokenRequester: TokenRequesting
    private let browser: BrowserAuthorizationSession
    private let random: RandomBytesGenerator
    private let sha256: @Sendable (Data) -> Data
    private let config: OAuthClientConfig

    public init(
        discovery: AccountDiscovering,
        authorizationRequester: AuthorizationRequesting,
        tokenRequester: TokenRequesting,
        browser: BrowserAuthorizationSession,
        random: RandomBytesGenerator,
        sha256: @escaping @Sendable (Data) -> Data,
        config: OAuthClientConfig
    ) {
        self.discovery = discovery
        self.authorizationRequester = authorizationRequester
        self.tokenRequester = tokenRequester
        self.browser = browser
        self.random = random
        self.sha256 = sha256
        self.config = config
    }

    public func login(account: String) async throws -> OAuthLoginResult {
        let discovered = try await discovery.discover(account: account)

        let verifier = PKCE.generateVerifier(randomBytes: random.bytes)
        let pkce = PKCE.make(verifier: verifier, sha256: sha256)
        let state = AuthorizationRequest.generateState(randomBytes: random.bytes)

        let request = AuthorizationRequest(
            config: config, pkce: pkce, state: state, loginHint: account
        )
        let par = try await authorizationRequester.push(
            metadata: discovered.metadata, request: request
        )
        let authorizationURL = try AuthorizationRequestService.authorizationURL(
            metadata: discovered.metadata, config: config, requestURI: par.requestURI
        )

        let callbackURL = try await browser.authenticate(
            url: authorizationURL, callbackScheme: config.callbackScheme
        )
        let callback = try OAuthCallback.parse(url: callbackURL)
        guard callback.state == state else {
            throw OAuthError.stateMismatch
        }

        let tokens = try await tokenRequester.requestToken(
            metadata: discovered.metadata,
            config: config,
            grant: .authorizationCode(code: callback.code, codeVerifier: verifier)
        )
        return OAuthLoginResult(
            did: tokens.sub,
            pds: discovered.pds,
            authorizationServerIssuer: discovered.authorizationServerIssuer,
            tokens: tokens
        )
    }
}
