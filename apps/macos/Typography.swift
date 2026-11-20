import SwiftUI
import AppKit

/// The app's current text font family. Centralized here because SwiftUI has no
/// single modifier to swap the whole app's font family (only `fontDesign`, which
/// affects the Latin SF face, not the Japanese one), and every view sets its own
/// text style. `FontSettingsStore` owns the user's choice and keeps `family` in
/// sync; views re-read it whenever the store publishes a change.
///
/// The default is the system font (`systemFamily`), as in the desktop prototype:
/// San Francisco for Latin text, with macOS falling back to Hiragino for
/// Japanese. Any installed family can be chosen instead. Marked `nonisolated(unsafe)` because it is
/// only ever read/written on the main thread (UI), where strict concurrency would
/// otherwise complain about the mutable global.
enum AppTypography {
    /// Stands for the system font; not a real family name.
    static let systemFamily = ".system"
    static let systemDefaultFamily = systemFamily
    nonisolated(unsafe) static var family = systemDefaultFamily

    /// The macOS-standard point size of the body text style (≈13pt). All other
    /// styles keep their standard ratio against this, so changing `baseSize` scales
    /// the whole hierarchy while preserving it. (macOS/AppKit has no Dynamic Type,
    /// so sizes are effectively fixed and an absolute point value is natural.)
    static let referenceBodySize = NSFont.preferredFont(forTextStyle: .body).pointSize

    /// The user-chosen body point size that drives every text size. Same
    /// main-thread-only rationale as `family` for `nonisolated(unsafe)`.
    static let minBaseSize: CGFloat = 11
    static let maxBaseSize: CGFloat = 24
    /// One point above the system body size: Japanese posts at the 13pt system
    /// size were hard to read in the timeline.
    static var defaultBaseSize: CGFloat { referenceBodySize + 1 }
    nonisolated(unsafe) static var baseSize: CGFloat = defaultBaseSize

    /// The point size `Font.app(style)` renders at, for spacing that must scale
    /// with the text.
    static func pointSize(_ style: Font.TextStyle) -> CGFloat {
        Font.standardSize(style) * sizeRatio
    }

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
        let size = AppTypography.pointSize(style)
        let font = AppTypography.family == AppTypography.systemFamily
            ? Font.system(size: size)
            : Font.custom(AppTypography.family, size: size, relativeTo: style)
        return font.weight(weight ?? defaultWeight(style))
    }

    /// A font at a fixed point size in the app's current family, mirroring
    /// `.system(size:weight:)`. The user's size scaling still applies.
    static func appSize(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaled = size * AppTypography.sizeRatio
        let font = AppTypography.family == AppTypography.systemFamily
            ? Font.system(size: scaled)
            : Font.custom(AppTypography.family, fixedSize: scaled)
        return font.weight(weight)
    }

    private static func defaultWeight(_ style: Font.TextStyle) -> Font.Weight {
        style == .headline ? .semibold : .regular
    }

    /// The macOS standard point size for a text style, read from `NSFont` so the
    /// custom font matches the system metrics exactly.
    fileprivate static func standardSize(_ style: Font.TextStyle) -> CGFloat {
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
