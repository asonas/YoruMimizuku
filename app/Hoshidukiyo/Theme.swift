import SwiftUI
import HoshidukiyoKit

extension Color {
    /// Bridges a framework-agnostic `PaletteColor` into a SwiftUI `Color`, keeping
    /// its color space so display-p3 values are rendered with their wider gamut.
    init(_ palette: PaletteColor) {
        let space: Color.RGBColorSpace = palette.colorSpace == .displayP3 ? .displayP3 : .sRGB
        self.init(space, red: palette.red, green: palette.green, blue: palette.blue, opacity: palette.opacity)
    }
}

/// Holds the active `ThemePalette` and exposes it as SwiftUI colors. The palette is
/// seeded from a randoma11y URL (see `RandomA11yURLParser`) and persisted so it
/// survives launches. Background and text can be swapped without re-entering a URL.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var palette: ThemePalette
    /// The randoma11y URL last applied, shown back in the settings screen.
    @Published private(set) var sourceURL: String

    private let defaults: UserDefaults
    private static let paletteKey = "theme.palette"
    private static let sourceURLKey = "theme.sourceURL"

    /// #2563eb (blue-600). randoma11y supplies only two colors, so the brand accent
    /// stays fixed rather than being derived from the pair.
    private static let accentColor = Color(.sRGB, red: 0.145, green: 0.388, blue: 0.922, opacity: 1)

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

    var background: Color { Color(palette.background) }
    var surface: Color { Color(palette.surface) }
    var primaryText: Color { Color(palette.text) }
    var secondaryText: Color { Color(palette.secondaryText) }
    var avatarPlaceholder: Color { Color(palette.avatarPlaceholder) }
    var divider: Color { Color(palette.divider) }
    var accent: Color { Self.accentColor }
}
