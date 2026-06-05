import SwiftUI
import AppKit

/// The app's current text font family. Centralized here because SwiftUI has no
/// single modifier to swap the whole app's font family (only `fontDesign`, which
/// affects the Latin SF face, not the Japanese one), and every view sets its own
/// text style. `FontSettingsStore` owns the user's choice and keeps `family` in
/// sync; views re-read it whenever the store publishes a change.
///
/// The default is `Hiragino Sans` (ヒラギノ角ゴシック) — Apple's bundled Japanese
/// face, so no font files are shipped. Marked `nonisolated(unsafe)` because it is
/// only ever read/written on the main thread (UI), where strict concurrency would
/// otherwise complain about the mutable global.
enum AppTypography {
    static let systemDefaultFamily = "Hiragino Sans"
    nonisolated(unsafe) static var family = systemDefaultFamily

    /// The macOS-standard point size of the body text style (≈13pt). All other
    /// styles keep their standard ratio against this, so changing `baseSize` scales
    /// the whole hierarchy while preserving it. (macOS/AppKit has no Dynamic Type,
    /// so sizes are effectively fixed and an absolute point value is natural.)
    static let referenceBodySize = NSFont.preferredFont(forTextStyle: .body).pointSize

    /// The user-chosen body point size that drives every text size. Defaults to the
    /// system standard. Same main-thread-only rationale as `family` for
    /// `nonisolated(unsafe)`.
    static let minBaseSize: CGFloat = 11
    static let maxBaseSize: CGFloat = 24
    static var defaultBaseSize: CGFloat { referenceBodySize }
    nonisolated(unsafe) static var baseSize: CGFloat = NSFont.preferredFont(forTextStyle: .body).pointSize

    /// How much to scale standard sizes by, given the chosen body size.
    static var sizeRatio: CGFloat { baseSize / referenceBodySize }
}

/// App-wide typography helpers. All `.font(...)` calls route through these so the
/// whole UI shares one family. Monospaced / monospaced-digit usages intentionally
/// stay on the system font, since the chosen family may not be monospaced.
extension Font {
    /// A font sized to a Dynamic Type text style, scaling with it, in the app's
    /// current family. `.headline` keeps its semibold emphasis unless overridden.
    static func app(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let size = standardSize(style) * AppTypography.sizeRatio
        return Font.custom(AppTypography.family, size: size, relativeTo: style)
            .weight(weight ?? defaultWeight(style))
    }

    /// A font at a fixed point size in the app's current family, mirroring
    /// `.system(size:weight:)`. The user's size scaling still applies.
    static func appSize(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom(AppTypography.family, fixedSize: size * AppTypography.sizeRatio).weight(weight)
    }

    private static func defaultWeight(_ style: Font.TextStyle) -> Font.Weight {
        style == .headline ? .semibold : .regular
    }

    /// The macOS standard point size for a text style, read from `NSFont` so the
    /// custom font matches the system metrics exactly.
    private static func standardSize(_ style: Font.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: nsTextStyle(style)).pointSize
    }

    private static func nsTextStyle(_ style: Font.TextStyle) -> NSFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}
