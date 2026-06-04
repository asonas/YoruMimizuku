import Foundation
import Security

/// Source of cryptographically secure random bytes. Injected into PKCE verifier
/// and OAuth state generation so tests can supply deterministic bytes. One of
/// the OS-touchpoint abstractions in the design.
public protocol RandomBytesGenerator: Sendable {
    func bytes(_ count: Int) -> Data
}

/// Apple implementation backed by `SecRandomCopyBytes`. Traps via precondition
/// if the OS RNG fails, which in practice does not happen on Apple platforms.
/// Failing fast avoids producing empty or predictable PKCE verifiers and OAuth
/// state from a silent empty-buffer fallback.
public struct SecRandomBytesGenerator: RandomBytesGenerator {
    public init() {}

    public func bytes(_ count: Int) -> Data {
        guard count > 0 else { return Data() }
        var buffer = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &buffer)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        return Data(buffer)
    }
}
