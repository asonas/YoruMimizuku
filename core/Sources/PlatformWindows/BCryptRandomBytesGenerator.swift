#if canImport(WinSDK)
import Foundation
import WinSDK
import BlueskyCore

/// Windows `RandomBytesGenerator` backed by `BCryptGenRandom` with the system
/// preferred RNG. Mirrors `SecRandomBytesGenerator` on Apple: it traps if the OS
/// RNG fails so a silent empty buffer can never weaken a PKCE verifier or OAuth
/// state value.
public struct BCryptRandomBytesGenerator: RandomBytesGenerator {
    // BCRYPT_USE_SYSTEM_PREFERRED_RNG: use the system-preferred RNG with a null
    // algorithm handle (the macro is not imported into Swift).
    private static let useSystemPreferredRNG: ULONG = 0x0000_0002

    public init() {}

    public func bytes(_ count: Int) -> Data {
        guard count > 0 else { return Data() }
        var buffer = [UInt8](repeating: 0, count: count)
        let status: NTSTATUS = buffer.withUnsafeMutableBufferPointer { ptr in
            BCryptGenRandom(nil, ptr.baseAddress, ULONG(count), Self.useSystemPreferredRNG)
        }
        precondition(status == 0, "BCryptGenRandom failed with status \(status)")
        return Data(buffer)
    }
}
#endif
