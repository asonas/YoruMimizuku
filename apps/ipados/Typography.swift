import SwiftUI
import UIKit

/// The app's current text font family. Centralized here because SwiftUI has no
/// single modifier to swap the whole app's font family (only `fontDesign`, which
/// affects the Latin SF face, not the Japanese one), and every view sets its own
/// text style.
///
/// The default is `Hiragino Sans` (ヒラギノ角ゴシック) — Apple's bundled Japanese
/// face, so no font files are shipped. Unlike macOS, the iPad target does not yet
/// expose a font-family / size picker (see
/// `2026-06-24-yorumimizuku-ipados-parity-design.md` §3), so `family` is fixed and
/// `sizeRatio` is 1. The hooks are kept so a future settings screen can drive them.
enum AppTypography {
    static let systemDefaultFamily = "Hiragino Sans"
    nonisolated(unsafe) static var family = systemDefaultFamily

    /// The standard point size of the body text style. All other styles keep their
    /// standard ratio against the system metrics via Dynamic Type, so a custom font
    /// matches the platform hierarchy. On iOS this also respects Dynamic Type.
    static let referenceBodySize = UIFont.preferredFont(forTextStyle: .body).pointSize

    /// How much to scale standard sizes by. Fixed at 1 on iPad until a size picker
    /// exists; the macOS app drives this from a user-chosen base size.
    static var sizeRatio: CGFloat { 1 }
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

    /// The standard point size for a text style, read from `UIFont` so the custom
    /// font matches the system metrics exactly (and respects Dynamic Type).
    private static func standardSize(_ style: Font.TextStyle) -> CGFloat {
        UIFont.preferredFont(forTextStyle: uiTextStyle(style)).pointSize
    }

    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
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
