import Foundation

/// Why a randoma11y URL could not be turned into a `ThemePalette`.
public enum RandomA11yParseError: Error, Equatable {
    case invalidURL
    case wrongHost
    case missingColors
    case unsupportedColor(String)
}

/// Parses randoma11y.com share URLs into a `ThemePalette`. The first path segment
/// is the background, the second is the text — matching the site's own ordering.
/// Two color encodings are supported:
///   - hex, percent-encoded:   `https://randoma11y.com/%2344403c/%23fafaf9`
///   - CSS `color(display-p3 r g b)`: `.../color(display-p3%200.0%200.1%200.9)/...`
public enum RandomA11yURLParser {
    public static func parse(_ string: String) throws -> ThemePalette {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), components.scheme != nil else {
            throw RandomA11yParseError.invalidURL
        }
        guard let host = components.host, host.contains("randoma11y.com") else {
            throw RandomA11yParseError.wrongHost
        }

        let segments = components.percentEncodedPath
            .split(separator: "/")
            .map(String.init)
            .compactMap { $0.removingPercentEncoding }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard segments.count >= 2 else {
            throw RandomA11yParseError.missingColors
        }

        return ThemePalette(
            background: try parseColor(segments[0]),
            text: try parseColor(segments[1])
        )
    }

    private static func parseColor(_ raw: String) throws -> PaletteColor {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") {
            return try parseHex(value)
        }
        if value.lowercased().hasPrefix("color(") {
            return try parseColorFunction(value)
        }
        throw RandomA11yParseError.unsupportedColor(value)
    }

    private static func parseHex(_ value: String) throws -> PaletteColor {
        let digits = Array(value.dropFirst())

        func component(_ first: Character, _ second: Character) -> Double? {
            UInt8(String([first, second]), radix: 16).map { Double($0) / 255 }
        }

        let red: Double?
        let green: Double?
        let blue: Double?
        let alpha: Double

        switch digits.count {
        case 6, 8:
            red = component(digits[0], digits[1])
            green = component(digits[2], digits[3])
            blue = component(digits[4], digits[5])
            alpha = digits.count == 8 ? (component(digits[6], digits[7]) ?? 1) : 1
        case 3, 4:
            red = component(digits[0], digits[0])
            green = component(digits[1], digits[1])
            blue = component(digits[2], digits[2])
            alpha = digits.count == 4 ? (component(digits[3], digits[3]) ?? 1) : 1
        default:
            throw RandomA11yParseError.unsupportedColor(value)
        }

        guard let r = red, let g = green, let b = blue else {
            throw RandomA11yParseError.unsupportedColor(value)
        }
        return PaletteColor(colorSpace: .sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    private static func parseColorFunction(_ value: String) throws -> PaletteColor {
        guard let open = value.firstIndex(of: "("), value.hasSuffix(")") else {
            throw RandomA11yParseError.unsupportedColor(value)
        }
        let inner = String(value[value.index(after: open)..<value.index(before: value.endIndex)])
        let tokens = inner.split { $0 == " " || $0 == "\t" }.map(String.init)
        guard let spaceToken = tokens.first else {
            throw RandomA11yParseError.unsupportedColor(value)
        }

        let colorSpace: ColorSpaceModel
        switch spaceToken.lowercased() {
        case "display-p3":
            colorSpace = .displayP3
        case "srgb":
            colorSpace = .sRGB
        default:
            throw RandomA11yParseError.unsupportedColor(value)
        }

        let numbers = tokens.dropFirst().compactMap { Double($0.replacingOccurrences(of: "%", with: "")) }
        guard numbers.count >= 3 else {
            throw RandomA11yParseError.unsupportedColor(value)
        }
        return PaletteColor(
            colorSpace: colorSpace,
            red: numbers[0],
            green: numbers[1],
            blue: numbers[2],
            opacity: numbers.count >= 4 ? numbers[3] : 1
        )
    }
}
