import XCTest
@testable import YoruMimizukuKit

final class ThemePaletteTests: XCTestCase {
    func test_defaultMatchesStonePalette() {
        let palette = ThemePalette.default
        XCTAssertEqual(palette.background.colorSpace, .sRGB)
        XCTAssertEqual(palette.background.red, 68 / 255, accuracy: 0.001)
        XCTAssertEqual(palette.text.red, 250 / 255, accuracy: 0.001)
    }

    func test_swappedExchangesBackgroundAndText() {
        let palette = ThemePalette.default
        let swapped = palette.swapped()
        XCTAssertEqual(swapped.background, palette.text)
        XCTAssertEqual(swapped.text, palette.background)
    }

    func test_swappingTwiceReturnsToOriginal() {
        let palette = ThemePalette.default
        XCTAssertEqual(palette.swapped().swapped(), palette)
    }

    func test_dividerUsesTextColorWithLowOpacity() {
        let palette = ThemePalette.default
        XCTAssertEqual(palette.divider.red, palette.text.red, accuracy: 0.001)
        XCTAssertLessThan(palette.divider.opacity, 0.2)
    }

    func test_surfaceSitsBetweenBackgroundAndText() {
        let palette = ThemePalette.default
        // background is dark, text is light, so surface should be slightly lighter than background.
        XCTAssertGreaterThan(palette.surface.red, palette.background.red)
        XCTAssertLessThan(palette.surface.red, palette.text.red)
    }

    func test_blendedTowardMovesComponentsByFraction() {
        let black = PaletteColor(colorSpace: .sRGB, red: 0, green: 0, blue: 0)
        let white = PaletteColor(colorSpace: .sRGB, red: 1, green: 1, blue: 1)
        let mid = black.blended(toward: white, fraction: 0.5)
        XCTAssertEqual(mid.red, 0.5, accuracy: 0.001)
        XCTAssertEqual(mid.green, 0.5, accuracy: 0.001)
        XCTAssertEqual(mid.blue, 0.5, accuracy: 0.001)
    }
}
