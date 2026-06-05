import Foundation
import BlueskyCore
#if canImport(os)
import os

/// Apple `SignpostTracing` backed by `OSSignposter`. Intervals show up in
/// Instruments (Points of Interest / custom intervals) under the app's
/// subsystem. Signposts are near-zero cost when no Instruments tool is attached.
public struct OSSignpostTracing: SignpostTracing {
    private let signposter: OSSignposter

    public init(_ signposter: OSSignposter) {
        self.signposter = signposter
    }

    /// Tracer for end-to-end timeline load intervals.
    public static let timeline = OSSignpostTracing(PerfSignpost.timeline)

    public func beginInterval(_ name: StaticString) -> (_ message: String) -> Void {
        let state = signposter.beginInterval(name)
        let signposter = self.signposter
        return { message in
            signposter.endInterval(name, state, "\(message)")
        }
    }
}
#endif
