import SwiftUI
import HoshidukiyoKit

extension Color {
    /// Build a color from a 0xRRGGBB hex literal.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Bridges a framework-agnostic `PaletteColor` into a SwiftUI `Color`, keeping
    /// its color space so display-p3 values are rendered with their wider gamut.
    init(_ palette: PaletteColor) {
        let space: Color.RGBColorSpace = palette.colorSpace == .displayP3 ? .displayP3 : .sRGB
        self.init(space, red: palette.red, green: palette.green, blue: palette.blue, opacity: palette.opacity)
    }
}

/// Holds the active `ThemePalette` and exposes the full "Nocturne" set of semantic
/// colors derived from it. The palette is seeded from a randoma11y URL (see
/// `RandomA11yURLParser`) and persisted so it survives launches; background and
/// text can be swapped without re-entering a URL. Only two colors come from
/// randoma11y, so neutral surfaces/dividers are blended from the pair while the
/// brand accent and star stay fixed.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var palette: ThemePalette
    /// The randoma11y URL last applied, shown back in the settings screen.
    @Published private(set) var sourceURL: String

    private let defaults: UserDefaults
    private static let paletteKey = "theme.palette"
    private static let sourceURLKey = "theme.sourceURL"

    /// Moonlit indigo — links, the active source, reply markers, controls.
    private static let accentColor = Color(hex: 0x8E9DFF)
    /// Warm gold — reserved for the brand star.
    private static let starColor = Color(hex: 0xE7C46B)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.paletteKey),
           let stored = try? JSONDecoder().decode(ThemePalette.self, from: data) {
            palette = stored
        } else {
            palette = .default
        }
        sourceURL = defaults.string(forKey: Self.sourceURLKey) ?? ""
    }

    /// Parses `urlString` and adopts its palette, throwing `RandomA11yParseError`
    /// (surfaced in the settings screen) when the URL is not a valid randoma11y link.
    func apply(urlString: String) throws {
        let parsed = try RandomA11yURLParser.parse(urlString)
        palette = parsed
        sourceURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    /// Swaps which color is the background and which is the text.
    func swap() {
        palette = palette.swapped()
        persist()
    }

    /// Restores the built-in warm-stone palette and forgets the stored URL.
    func reset() {
        palette = .default
        sourceURL = ""
        defaults.removeObject(forKey: Self.paletteKey)
        defaults.removeObject(forKey: Self.sourceURLKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(palette) {
            defaults.set(data, forKey: Self.paletteKey)
        }
        defaults.set(sourceURL, forKey: Self.sourceURLKey)
    }

    // MARK: - Semantic colors

    var background: Color { Color(palette.background) }
    var surface: Color { Color(palette.surface) }
    var surfaceElevated: Color { Color(palette.background.blended(toward: palette.text, fraction: 0.22)) }

    var accent: Color { Self.accentColor }
    var star: Color { Self.starColor }

    var primaryText: Color { Color(palette.text) }
    var secondaryText: Color { Color(palette.secondaryText) }
    var tertiaryText: Color { Color(palette.text.blended(toward: palette.background, fraction: 0.45)) }
    var avatarPlaceholder: Color { Color(palette.avatarPlaceholder) }

    var divider: Color { Color(palette.divider) }
    var hairline: Color { Color(palette.text.withOpacity(0.06)) }
    var rowHover: Color { Color(palette.text.withOpacity(0.05)) }

    private var canvasTop: Color { Color(palette.background.blended(toward: palette.text, fraction: 0.14)) }
    private var canvasBottom: Color { background }

    /// The full-window night canvas: a vertical warm gradient lit by a soft star
    /// glow in the top-trailing corner, like a moon just out of frame.
    var canvas: some View {
        LinearGradient(
            colors: [canvasTop, canvasBottom],
            startPoint: .top, endPoint: .bottom
        )
        .overlay(alignment: .topTrailing) {
            RadialGradient(
                colors: [star.opacity(0.12), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 420
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}
