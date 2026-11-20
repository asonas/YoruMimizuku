import SwiftUI
import AppKit
import YoruMimizukuKit

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

extension NSColor {
    convenience init(_ palette: PaletteColor) {
        switch palette.colorSpace {
        case .displayP3:
            self.init(displayP3Red: palette.red, green: palette.green, blue: palette.blue, alpha: palette.opacity)
        case .sRGB:
            self.init(srgbRed: palette.red, green: palette.green, blue: palette.blue, alpha: palette.opacity)
        }
    }
}

/// The window's colors: the desktop prototype's light and dark tokens
/// (`DesignTokens`), following the system appearance. A randoma11y URL, when set,
/// replaces only the background and text pair, oriented to the appearance; the
/// accent and reaction colors stay the prototype's. Each color resolves per
/// appearance at draw time, so light/dark switches need no state here.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var palette: ThemePalette
    /// The randoma11y URL last applied, shown back in the settings screen. Empty
    /// means the prototype's own background and text.
    @Published private(set) var sourceURL: String

    private let defaults: UserDefaults
    private static let paletteKey = "theme.palette"
    private static let sourceURLKey = "theme.sourceURL"

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

    /// Parses `urlString` and adopts its pair, throwing `RandomA11yParseError`
    /// (surfaced in the settings screen) when the URL is not a valid randoma11y link.
    func apply(urlString: String) throws {
        let parsed = try RandomA11yURLParser.parse(urlString)
        palette = parsed
        sourceURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    /// Returns to the prototype's colors and forgets the stored URL.
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

    /// The randoma11y pair in effect, if any.
    private var override: ThemePalette? { sourceURL.isEmpty ? nil : palette }

    /// A color that picks its token for the appearance it is drawn in.
    private func token(_ pick: @escaping @Sendable (DesignTokens) -> PaletteColor) -> Color {
        let override = self.override
        // `@Sendable` keeps the provider off the main actor: AppKit may resolve a
        // dynamic color on any thread, and a main-actor closure would trap there.
        return Color(nsColor: NSColor(name: nil) { @Sendable appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(pick(DesignTokens.resolve(dark: dark, override: override)))
        })
    }

    // MARK: - Semantic colors

    var background: Color { token(\.content) }
    var surface: Color { token(\.chrome) }
    var surfaceElevated: Color { token(\.field) }
    var sidebar: Color { token(\.side) }

    var accent: Color { token(\.accent) }
    /// Text and icons drawn on an accent fill.
    var accentForeground: Color { token(\.accentForeground) }
    var accentTint: Color { token(\.accentTint) }
    var like: Color { token(\.like) }
    var repost: Color { token(\.repost) }
    var warn: Color { token(\.warn) }
    var warnTint: Color { token(\.warnTint) }
    var proto: Color { token(\.proto) }
    var protoTint: Color { token(\.protoTint) }
    /// Neutral icons for empty and error states.
    var star: Color { token(\.fg3) }

    var primaryText: Color { token(\.fg) }
    var secondaryText: Color { token(\.fg2) }
    /// Handles, timestamps and counts; at least 4.5:1 on the background.
    var tertiaryText: Color { token(\.fg3) }
    var avatarPlaceholder: Color { token(\.selection) }

    var divider: Color { token(\.separator) }
    var hairline: Color { token(\.separator) }
    var rowHover: Color { token(\.hover) }
    var selection: Color { token(\.selection) }

    /// The plain content background behind feeds and panes.
    var canvas: some View {
        background.ignoresSafeArea()
    }
}
