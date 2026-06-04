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
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let session = ASWebAuthenticationSession(
                    url: url, callbackURLScheme: callbackScheme
                ) { [weak self] callbackURL, error in
                    self?.activeSession = nil
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(throwing: BrowserError.cancelled)
                    }
                }
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
