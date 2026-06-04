import Foundation

/// A logged-in account persisted to secure storage. Holds the OAuth tokens and
/// the DPoP private key as raw bytes (the Apple wiring layer restores it into a
/// P-256 key); this keeps the account layer free of CryptoKit.
public struct PersistedAccount: Codable, Equatable, Sendable {
    public var did: String
    public var handle: String?
    public var pds: URL
    public var issuer: String
    public var accessToken: String
    public var refreshToken: String?
    public var scope: String?
    /// The DPoP P-256 private key as raw bytes. Security boundary note: this key
    /// is serialized into the same JSON blob as the tokens and that whole blob is
    /// written to a single Keychain item, so the private key never leaves
    /// Keychain protection. It is held as `Data` (not a CryptoKit type) so this
    /// layer stays platform-agnostic.
    public var dpopPrivateKeyRaw: Data

    public init(
        did: String,
        handle: String?,
        pds: URL,
        issuer: String,
        accessToken: String,
        refreshToken: String?,
        scope: String?,
        dpopPrivateKeyRaw: Data
    ) {
        self.did = did
        self.handle = handle
        self.pds = pds
        self.issuer = issuer
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.scope = scope
        self.dpopPrivateKeyRaw = dpopPrivateKeyRaw
    }

    /// Build from a successful login plus the DPoP key used during that login.
    public init(loginResult: OAuthLoginResult, handle: String?, dpopPrivateKeyRaw: Data) {
        self.init(
            did: loginResult.did,
            handle: handle,
            pds: loginResult.pds,
            issuer: loginResult.authorizationServerIssuer,
            accessToken: loginResult.tokens.accessToken,
            refreshToken: loginResult.tokens.refreshToken,
            scope: loginResult.tokens.scope,
            dpopPrivateKeyRaw: dpopPrivateKeyRaw
        )
    }
}

/// The index of known accounts and which one is current.
public struct AccountsIndex: Codable, Equatable, Sendable {
    public var dids: [String]
    public var currentDID: String?

    public init(dids: [String] = [], currentDID: String? = nil) {
        self.dids = dids
        self.currentDID = currentDID
    }
}
