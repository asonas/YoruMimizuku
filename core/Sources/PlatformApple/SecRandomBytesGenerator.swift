import Foundation
import BlueskyCore
#if canImport(Security)
import Security
#endif

/// Apple implementation backed by `SecRandomCopyBytes`. Traps via precondition
/// if the OS RNG fails, which in practice does not happen on Apple platforms.
/// Failing fast avoids producing empty or predictable PKCE verifiers and OAuth
/// state from a silent empty-buffer fallback.
#if canImport(Security)
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
#endif
