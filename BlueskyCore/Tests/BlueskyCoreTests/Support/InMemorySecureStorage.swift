import Foundation
@testable import BlueskyCore

/// In-memory `SecureStorage` for tests. `@unchecked Sendable`: used serially
/// within async tests, matching the existing `FakeHTTPClient` convention.
final class InMemorySecureStorage: SecureStorage, @unchecked Sendable {
    private var items: [String: Data] = [:]

    func set(_ data: Data, for key: String) throws { items[key] = data }
    func data(for key: String) throws -> Data? { items[key] }
    func remove(for key: String) throws { items[key] = nil }
}
