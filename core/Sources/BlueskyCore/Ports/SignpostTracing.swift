import Foundation

/// Abstracts performance-interval tracing (Apple: `os.signpost`) so the pure
/// view-model layer does not depend on `os`. The Apple adapter (`OSSignpostTracing`)
/// lives in PlatformApple; other platforms and tests use `NoopSignpostTracing`.
///
/// One OS-touchpoint port in the design, alongside `SecureStorage`,
/// `DPoPCryptoProvider`, `HTTPClient`, and `RandomBytesGenerator`.
public protocol SignpostTracing: Sendable {
    /// Begin a named interval. Returns a closure that ends the interval,
    /// attaching a final message (shown in Instruments). The interval is
    /// identified by `name`, so begin/end share the same static string.
    func beginInterval(_ name: StaticString) -> (_ message: String) -> Void
}

/// No-op tracer used when no platform tracer is injected (unit tests and
/// non-Apple platforms that have no signpost facility yet).
public struct NoopSignpostTracing: SignpostTracing {
    public init() {}

    public func beginInterval(_ name: StaticString) -> (_ message: String) -> Void {
        { _ in }
    }
}
