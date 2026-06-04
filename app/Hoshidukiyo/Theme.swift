import SwiftUI

extension Color {
    /// Build a color from a 0xRRGGBB hex literal.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// "Nocturne reading room" theme: a warm-stone night canvas with a faint
/// top-trailing moonglow, a moonlit-indigo accent, and a single gold "star" used
/// sparingly for the wordmark. High text contrast over the dark warm ground.
enum Theme {
    static let canvasTop = Color(hex: 0x4A443F)
    static let canvasBottom = Color(hex: 0x2E2A26)
    /// Solid stand-in for the canvas where a flat color is needed.
    static let background = canvasBottom
    static let surface = Color(hex: 0x57534E)
    static let surfaceElevated = Color(hex: 0x645F59)

    /// Moonlit indigo — links, the active source, reply markers, controls.
    static let accent = Color(hex: 0x8E9DFF)
    /// Warm gold — reserved for the brand star.
    static let star = Color(hex: 0xE7C46B)

    static let primaryText = Color(hex: 0xFAFAF9)
    static let secondaryText = Color(hex: 0xD6D3D1)
    static let tertiaryText = Color(hex: 0xA8A29E)
    static let avatarPlaceholder = Color(hex: 0x78716C)

    static let divider = Color.white.opacity(0.10)
    static let hairline = Color.white.opacity(0.06)
    static let rowHover = Color.white.opacity(0.05)

    /// The full-window night canvas: a vertical warm gradient lit by a soft gold
    /// glow in the top-trailing corner, like a moon just out of frame.
    static var canvas: some View {
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
