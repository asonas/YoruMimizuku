#if canImport(os)
import os

/// Centralized `OSSignposter` loggers for performance profiling. The signposts
/// show up in Instruments (Points of Interest / custom intervals) grouped under
/// the app's subsystem, so timeline loads, image work, and render milestones can
/// be lined up against Time Profiler and Animation Hitches in the same trace.
///
/// Signposts are near-zero cost when no Instruments tool is attached, so these
/// stay compiled into Release builds rather than being gated behind `#if DEBUG`.
public enum PerfSignpost {
    public static let subsystem = "as.ason.YoruMimizuku"

    /// Timeline fetch + mapping intervals.
    public static let timeline = OSSignposter(subsystem: subsystem, category: "Timeline")
    /// Image load/decode intervals (used once images flow through an owned loader).
    public static let image = OSSignposter(subsystem: subsystem, category: "Image")
    /// Coarse render milestones, e.g. launch to first content.
    public static let render = OSSignposter(subsystem: subsystem, category: "Render")
}
#endif
