import Foundation

/// Runs the full OAuth login for a handle and persists the resulting account,
/// returning the account DID. The app provides the live implementation; tests
/// inject a stub. Keeps `LoginViewModel` free of OS/network concerns.
public protocol LoginPerforming: Sendable {
    func login(handle: String) async throws -> String
}
