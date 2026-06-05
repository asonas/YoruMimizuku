import XCTest
@testable import YoruMimizukuKit

final class RandomA11yURLParserTests: XCTestCase {
    private func assertColor(
        _ color: PaletteColor,
        space: ColorSpaceModel,
        red: Double,
        green: Double,
        blue: Double,
        opacity: Double = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(color.colorSpace, space, file: file, line: line)
        XCTAssertEqual(color.red, red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(color.green, green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(color.blue, blue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(color.opacity, opacity, accuracy: 0.001, file: file, line: line)
    }

    func test_parsesHexEncodedURL_firstIsBackgroundSecondIsText() throws {
        let palette = try RandomA11yURLParser.parse("https://randoma11y.com/%2344403c/%23fafaf9")
        assertColor(palette.background, space: .sRGB, red: 68 / 255, green: 64 / 255, blue: 60 / 255)
        assertColor(palette.text, space: .sRGB, red: 250 / 255, green: 250 / 255, blue: 249 / 255)
    }

    func test_parsesDisplayP3EncodedURL() throws {
        let url = "https://randoma11y.com/color(display-p3%200.042%200.194%200.967)/color(display-p3%200.941%200.973%200.922)"
        let palette = try RandomA11yURLParser.parse(url)
        assertColor(palette.background, space: .displayP3, red: 0.042, green: 0.194, blue: 0.967)
        assertColor(palette.text, space: .displayP3, red: 0.941, green: 0.973, blue: 0.922)
    }

    func test_parsesShorthandHex() throws {
        let palette = try RandomA11yURLParser.parse("https://randoma11y.com/%23fff/%23000")
        assertColor(palette.background, space: .sRGB, red: 1, green: 1, blue: 1)
        assertColor(palette.text, space: .sRGB, red: 0, green: 0, blue: 0)
    }

    func test_throwsWrongHostForNonRandomA11yURL() {
        XCTAssertThrowsError(try RandomA11yURLParser.parse("https://example.com/%2344403c/%23fafaf9")) { error in
            XCTAssertEqual(error as? RandomA11yParseError, .wrongHost)
        }
    }

    func test_throwsMissingColorsWhenOnlyOneColor() {
        XCTAssertThrowsError(try RandomA11yURLParser.parse("https://randoma11y.com/%2344403c")) { error in
            XCTAssertEqual(error as? RandomA11yParseError, .missingColors)
        }
    }

    func test_throwsInvalidURLForGarbage() {
        XCTAssertThrowsError(try RandomA11yURLParser.parse("not a url at all"))
    }

    func test_throwsUnsupportedColorForUnknownFormat() {
        XCTAssertThrowsError(try RandomA11yURLParser.parse("https://randoma11y.com/rgb(1,2,3)/%23fafaf9"))
    }
}
