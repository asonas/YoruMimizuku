import Foundation

/// Opens an authorization URL in a system browser session and resolves with the
/// redirect callback URL once the user approves. On Apple platforms this is
/// implemented with `ASWebAuthenticationSession`; tests inject a fake. One of the
/// OS-touchpoint abstractions in the design.
public protocol BrowserAuthorizationSession: Sendable {
    /// Present `url`, wait for a redirect whose scheme equals `callbackScheme`,
    /// and return the full callback URL. Throws if the user cancels or the
    /// session fails.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}
