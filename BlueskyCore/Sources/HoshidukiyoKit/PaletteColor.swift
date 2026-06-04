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

    public func withOpacity(_ opacity: Double) -> PaletteColor {
        PaletteColor(colorSpace: colorSpace, red: red, green: green, blue: blue, opacity: opacity)
    }
}
