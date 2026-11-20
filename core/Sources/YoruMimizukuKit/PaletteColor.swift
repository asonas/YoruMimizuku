import Foundation

/// The color space a `PaletteColor` is expressed in. randoma11y emits either hex
/// (sRGB) or `color(display-p3 ...)` values, so both must round-trip faithfully.
public enum ColorSpaceModel: String, Sendable, Codable, Equatable {
    case sRGB
    case displayP3
}

/// A framework-agnostic color: components in 0...1 plus the space they belong to.
/// Kept free of SwiftUI so it can be parsed and unit tested; the app maps it to a
/// SwiftUI `Color` at the edge.
public struct PaletteColor: Equatable, Sendable, Codable {
    public var colorSpace: ColorSpaceModel
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(colorSpace: ColorSpaceModel, red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.colorSpace = colorSpace
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    /// Linearly interpolates each component toward `other` by `fraction` (clamped
    /// to 0...1). The receiver's color space is preserved, which is correct when
    /// both colors share a space (the common randoma11y case).
    public func blended(toward other: PaletteColor, fraction: Double) -> PaletteColor {
        let f = min(max(fraction, 0), 1)
        return PaletteColor(
            colorSpace: colorSpace,
            red: red + (other.red - red) * f,
            green: green + (other.green - green) * f,
            blue: blue + (other.blue - blue) * f,
            opacity: opacity + (other.opacity - opacity) * f
        )
    }

    /// WCAG relative luminance (0 for black, 1 for white). Display-p3 components
    /// are treated as sRGB, which is close enough for ordering and contrast checks.
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio against `other`, from 1 to 21.
    public func contrastRatio(with other: PaletteColor) -> Double {
        let (a, b) = (relativeLuminance, other.relativeLuminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public func withOpacity(_ opacity: Double) -> PaletteColor {
        PaletteColor(colorSpace: colorSpace, red: red, green: green, blue: blue, opacity: opacity)
    }
}
