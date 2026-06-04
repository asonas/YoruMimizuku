import Foundation

/// Abstraction over a secure key/value store (Apple: Keychain). Keys are opaque
/// strings; values are raw `Data`. One of the OS-touchpoint abstractions in the
/// design. Tests inject an in-memory fake.
public protocol SecureStorage: Sendable {
    /// Store `data` under `key`, overwriting any existing value.
    func set(_ data: Data, for key: String) throws
    /// Return the stored value for `key`, or nil if absent.
    func data(for key: String) throws -> Data?
    /// Remove the value for `key` (no-op if absent).
    func remove(for key: String) throws
}
