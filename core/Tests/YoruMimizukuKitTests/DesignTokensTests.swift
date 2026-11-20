import XCTest
@testable import YoruMimizukuKit

final class DesignTokensTests: XCTestCase {
    private func hex(_ value: UInt32) -> PaletteColor {
        PaletteColor(
            colorSpace: .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    func testContrastRatioMatchesTheWCAGFormula() {
        XCTAssertEqual(hex(0x000000).contrastRatio(with: hex(0xFFFFFF)), 21, accuracy: 0.01)
        XCTAssertEqual(hex(0x777777).contrastRatio(with: hex(0xFFFFFF)), 4.48, accuracy: 0.01)
    }

    func testTheDefaultsAreThePrototypeTokens() {
        let light = DesignTokens.resolve(dark: false, override: nil)
        let dark = DesignTokens.resolve(dark: true, override: nil)

        XCTAssertEqual(light.content, hex(0xFFFFFF))
        XCTAssertEqual(light.accent, hex(0x0068DA))
        XCTAssertEqual(light.like, hex(0xD0335E))
        XCTAssertEqual(dark.content, hex(0x1E1E20))
        XCTAssertEqual(dark.accent, hex(0x2F8CFF))
        XCTAssertEqual(dark.repost, hex(0x4CC690))
    }

    /// Small secondary text (handles, times, counts) must stay at or above
    /// WCAG AA's 4.5:1 on the content background in both appearances.
    func testEveryTextTokenReadsAtAAOnTheContentBackground() {
        for dark in [false, true] {
            let tokens = DesignTokens.resolve(dark: dark, override: nil)
            for (name, color) in [("fg", tokens.fg), ("fg2", tokens.fg2), ("fg3", tokens.fg3)] {
                XCTAssertGreaterThanOrEqual(color.contrastRatio(with: tokens.content), 4.5, "\(name) dark=\(dark)")
            }
        }
    }

    /// A randoma11y pair replaces the background and text, lighter color first in
    /// light appearance and darker first in dark; the accent stays the prototype's.
    func testARandoma11yPairIsOrientedByAppearanceAndKeepsTheAccent() {
        let pair = ThemePalette(background: hex(0x1B2A41), text: hex(0xF4E9CD))

        let light = DesignTokens.resolve(dark: false, override: pair)
        let dark = DesignTokens.resolve(dark: true, override: pair)

        XCTAssertEqual(light.content, hex(0xF4E9CD))
        XCTAssertEqual(light.fg, hex(0x1B2A41))
        XCTAssertEqual(dark.content, hex(0x1B2A41))
        XCTAssertEqual(dark.fg, hex(0xF4E9CD))
        XCTAssertEqual(light.accent, hex(0x0068DA))
    }
}
