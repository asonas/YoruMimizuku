import Foundation
import AuthenticationServices
import AppKit
import BlueskyCore

/// `BrowserAuthorizationSession` backed by `ASWebAuthenticationSession`. Presents
/// the authorization URL in a secure system web view and resolves with the
/// redirect callback URL. Retains the in-flight session so it is not deallocated
/// before completion. `@unchecked Sendable`: all mutable state is touched only on
/// the main actor.
final class ASWebAuthBrowserSession: NSObject, BrowserAuthorizationSession,
    ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {

    enum BrowserError: Error { case failedToStart, cancelled }

    private var activeSession: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
            // ASWebAuthenticationSession invokes this completion handler on its
            // own XPC queue (SafariLaunchAgent), NOT the main thread. It must be
            // an explicitly @Sendable / non-isolated closure: if it inherits
            // @MainActor isolation (which happens when formed inside the
            // `Task { @MainActor }` below), the Swift runtime fires a
            // dispatch_assert_queue(main) check off the main queue and crashes.
            let completion: @Sendable (URL?, (any Error)?) -> Void = { [weak self] callbackURL, error in
                Task { @MainActor in self?.activeSession = nil }
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: BrowserError.cancelled)
                }
            }
            Task { @MainActor in
                let session = ASWebAuthenticationSession(
                    url: url, callbackURLScheme: callbackScheme, completionHandler: completion
                )
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.activeSession = session
                if !session.start() {
                    self.activeSession = nil
                    continuation.resume(throwing: BrowserError.failedToStart)
                }
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
