import Foundation

/// Source of cryptographically secure random bytes. Injected into PKCE verifier
/// and OAuth state generation so tests can supply deterministic bytes. One of
/// the OS-touchpoint abstractions in the design.
public protocol RandomBytesGenerator: Sendable {
    func bytes(_ count: Int) -> Data
}
