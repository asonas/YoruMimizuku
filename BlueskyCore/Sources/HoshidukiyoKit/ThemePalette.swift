/// The two anchor colors of the UI — background and text — plus the neutral tones
/// derived from them. randoma11y hands out exactly two accessible colors, so every
/// other surface/divider tone is blended from this pair to stay coherent.
public struct ThemePalette: Equatable, Sendable, Codable {
    public var background: PaletteColor
    public var text: PaletteColor

    public init(background: PaletteColor, text: PaletteColor) {
        self.background = background
        self.text = text
    }

    /// Swaps which color paints the background and which paints the text.
    public func swapped() -> ThemePalette {
        ThemePalette(background: text, text: background)
    }

    /// Bars, chips, and the composer: one small step from the background toward the
    /// text so they read as slightly elevated.
    public var surface: PaletteColor {
        background.blended(toward: text, fraction: 0.12)
    }

    /// Secondary text: the text color pulled partway toward the background so it
    /// recedes while staying legible.
    public var secondaryText: PaletteColor {
        text.blended(toward: background, fraction: 0.28)
    }

    /// Neutral fill shown until an avatar image loads.
    public var avatarPlaceholder: PaletteColor {
        background.blended(toward: text, fraction: 0.45)
    }

    /// Hairline divider: the text color at low opacity.
    public var divider: PaletteColor {
        text.withOpacity(0.12)
    }

    /// The default warm-stone pair (#44403c background / #fafaf9 text).
    public static let `default` = ThemePalette(
        background: PaletteColor(colorSpace: .sRGB, red: 68 / 255, green: 64 / 255, blue: 60 / 255),
        text: PaletteColor(colorSpace: .sRGB, red: 250 / 255, green: 250 / 255, blue: 249 / 255)
    )
}
