/// Where a post row places its media relative to the body text. `vertical` is the
/// narrow, single-column stack (Yorufukurou-style); `reflow` puts the body on the
/// left and media (images / video / link card) in a fixed-width rail on the right.
public enum TimelineMediaPlacement: Equatable, Sendable {
    case vertical
    case reflow
}

/// Pure layout math for the timeline post row. Kept free of CoreGraphics/SwiftUI so
/// it stays platform-neutral (shared with the Windows core) and unit-testable; the
/// macOS view converts these `Double`s to `CGFloat` at the call site.
public enum TimelineLayout {
    /// Region width (the body+media area, excluding avatar column and row padding)
    /// at or above which the row reflows to body-left / media-right.
    /// 680 = textMin(360) + columnGap(16) + mediaRailWidth(300), rounded.
    public static let reflowThreshold: Double = 680
    /// Fixed width of the right-hand media rail in reflow mode.
    public static let mediaRailWidth: Double = 300
    /// Gap between the text column and the media rail in reflow mode.
    public static let columnGap: Double = 16
    /// Upper bound on the body text column width, for readability.
    public static let maxTextColumnWidth: Double = 620
    /// Lowest allowed single-image aspect ratio (width/height); 0.8 == height ≤ 1.25×width.
    public static let minSingleImageRatio: Double = 0.8
    /// Highest allowed single-image aspect ratio (panorama clamp).
    public static let maxSingleImageRatio: Double = 5.0

    public static func placement(regionWidth: Double) -> TimelineMediaPlacement {
        regionWidth >= reflowThreshold ? .reflow : .vertical
    }

    public static func textColumnWidth(regionWidth: Double) -> Double {
        let remainder = regionWidth - columnGap - mediaRailWidth
        return min(maxTextColumnWidth, max(0, remainder))
    }

    public static func clampedSingleImageRatio(_ natural: Double) -> Double {
        min(max(natural, minSingleImageRatio), maxSingleImageRatio)
    }

    public static func isTallCropped(_ natural: Double) -> Bool {
        natural < minSingleImageRatio
    }
}
