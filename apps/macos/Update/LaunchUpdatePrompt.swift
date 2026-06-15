import Foundation

/// One-shot latch deciding whether the *next* update Sparkle surfaces should be
/// shown as a foreground dialog instead of the quiet gentle-reminder badge.
///
/// Periodic background checks deliberately stay gentle (badge only) so the app
/// never nags mid-session. The launch check is the exception: it arms the latch
/// before asking Sparkle to look, so a freshly published version greets the
/// user with the standard update dialog the moment they open the app. The latch
/// is consumed once and then falls back to the gentle behavior.
struct LaunchUpdatePrompt: Equatable {
    private(set) var isPending: Bool

    init(isPending: Bool = false) {
        self.isPending = isPending
    }

    mutating func arm() {
        isPending = true
    }

    /// Returns whether a launch-triggered prompt is pending and clears it, so a
    /// subsequent scheduled check falls back to the gentle badge.
    mutating func consume() -> Bool {
        defer { isPending = false }
        return isPending
    }
}
