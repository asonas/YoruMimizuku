/// The colors of the macOS window, taken from the desktop prototype (Lenses) in a
/// light and a dark set. A randoma11y pair, when set, replaces only the background
/// and text (and the neutrals derived from them); accent and reaction colors stay.
public struct DesignTokens: Equatable, Sendable {
    /// Post lists and panes.
    public var content: PaletteColor
    /// Toolbars and headers.
    public var chrome: PaletteColor
    /// The sidebar (translucent in the prototype).
    public var side: PaletteColor
    public var fg: PaletteColor
    public var fg2: PaletteColor
    /// Handles, times and counts.
    public var fg3: PaletteColor
    public var separator: PaletteColor
    public var hover: PaletteColor
    /// Selected rows: a dim fill under normal text.
    public var selection: PaletteColor
    public var accent: PaletteColor
    /// Text and icons drawn on an accent fill.
    public var accentForeground: PaletteColor
    public var accentTint: PaletteColor
    public var like: PaletteColor
    public var repost: PaletteColor
    public var warn: PaletteColor
    public var warnTint: PaletteColor
    /// Records from other AT Protocol apps.
    public var proto: PaletteColor
    public var protoTint: PaletteColor
    /// Text fields.
    public var field: PaletteColor

    /// The tokens for an appearance, with a randoma11y pair laid over the
    /// background and text when `override` is set.
    public static func resolve(dark: Bool, override: ThemePalette?) -> DesignTokens {
        var tokens = dark ? Self.dark : Self.light
        guard let override else { return tokens }
        let pair = override.oriented(dark: dark)
        let (bg, text) = (pair.background, pair.text)
        tokens.content = bg
        tokens.field = bg
        tokens.chrome = bg.blended(toward: text, fraction: 0.05)
        tokens.side = bg.blended(toward: text, fraction: 0.08)
        tokens.fg = text
        tokens.fg2 = text.blended(toward: bg, fraction: 0.28)
        tokens.fg3 = text.blended(toward: bg, fraction: 0.38)
        tokens.separator = text.withOpacity(0.1)
        tokens.hover = text.withOpacity(0.045)
        tokens.selection = text.withOpacity(0.08)
        return tokens
    }

    private static func hex(_ value: UInt32, _ opacity: Double = 1) -> PaletteColor {
        PaletteColor(
            colorSpace: .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: opacity
        )
    }

    // fg3 is darker (light) / lighter (dark) than the prototype's #85858b /
    // #7f7f85, which fall short of WCAG AA's 4.5:1 for small text.
    public static let light = DesignTokens(
        content: hex(0xFFFFFF), chrome: hex(0xF3F3F5), side: hex(0xE8E9EE, 0.78),
        fg: hex(0x1D1D1F), fg2: hex(0x5C5C62), fg3: hex(0x6E6E73),
        separator: hex(0x000000, 0.1), hover: hex(0x000000, 0.045), selection: hex(0x000000, 0.08),
        accent: hex(0x0068DA), accentForeground: hex(0xFFFFFF), accentTint: hex(0x0068DA, 0.1),
        like: hex(0xD0335E), repost: hex(0x1A7F5A), warn: hex(0x8A5300), warnTint: hex(0xFBF0DE),
        proto: hex(0x0E6E66), protoTint: hex(0xE2F3F0), field: hex(0xFFFFFF)
    )

    public static let dark = DesignTokens(
        content: hex(0x1E1E20), chrome: hex(0x2B2B2E), side: hex(0x2C2C30, 0.78),
        fg: hex(0xF2F2F5), fg2: hex(0xABABB0), fg3: hex(0x8E8E93),
        separator: hex(0xFFFFFF, 0.1), hover: hex(0xFFFFFF, 0.05), selection: hex(0xFFFFFF, 0.1),
        accent: hex(0x2F8CFF), accentForeground: hex(0xFFFFFF), accentTint: hex(0x2F8CFF, 0.18),
        like: hex(0xFF6B8E), repost: hex(0x4CC690), warn: hex(0xF2B65E), warnTint: hex(0x3A2B14),
        proto: hex(0x5FD3C4), protoTint: hex(0x133230), field: hex(0x2A2A2D)
    )
}
