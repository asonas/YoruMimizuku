import Foundation

/// Pragmatic OGP (Open Graph protocol) extraction from an HTML document, used to
/// build a `LinkCard` for a bare URL in a post body when the post carries no
/// external embed. Regex-based on purpose: link previews only need the handful
/// of `<meta>`/`<title>` tags in `<head>`, and a tolerant scan over the raw
/// markup beats pulling in a full HTML parser for that.
public enum OGP {
    /// Build a card from `html` for the page at `url`. Returns nil when neither
    /// `og:title` nor a `<title>` is present — a card with no title is noise.
    public static func parse(html: String, url: URL) -> LinkCard? {
        let title = metaContent(in: html, property: "og:title")
            ?? titleTag(in: html)
        guard let title, !title.isEmpty else { return nil }

        let description = metaContent(in: html, property: "og:description")
            ?? metaContent(in: html, name: "description")
            ?? ""
        let thumbURL = metaContent(in: html, property: "og:image")
            .flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }

        return LinkCard(url: url, title: title, description: description, thumbURL: thumbURL)
    }

    /// `<meta property="..." content="...">` in either attribute order.
    private static func metaContent(in html: String, property: String) -> String? {
        metaContent(in: html, attribute: "property", value: property)
            ?? metaContent(in: html, attribute: "name", value: property)
    }

    /// `<meta name="..." content="...">` in either attribute order.
    private static func metaContent(in html: String, name: String) -> String? {
        metaContent(in: html, attribute: "name", value: name)
    }

    private static func metaContent(in html: String, attribute: String, value: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: value)
        // <meta property="og:x" ... content="...">
        let forward = "<meta[^>]*\(attribute)\\s*=\\s*[\"']\(escaped)[\"'][^>]*content\\s*=\\s*[\"']([^\"']*)[\"']"
        // <meta content="..." ... property="og:x">
        let backward = "<meta[^>]*content\\s*=\\s*[\"']([^\"']*)[\"'][^>]*\(attribute)\\s*=\\s*[\"']\(escaped)[\"']"
        return firstCapture(forward, in: html).map(decodeEntities)
            ?? firstCapture(backward, in: html).map(decodeEntities)
    }

    private static func titleTag(in html: String) -> String? {
        firstCapture("<title[^>]*>([^<]*)</title>", in: html)
            .map(decodeEntities)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func firstCapture(_ pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let captured = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[captured])
    }

    /// Decode the named and numeric character references that commonly appear in
    /// meta content. Numeric references are decoded first so a literal "&amp;#39;"
    /// round-trips correctly (it must yield "&#39;", not an apostrophe).
    static func decodeEntities(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: range).reversed()
            for match in matches {
                guard let whole = Range(match.range, in: result),
                      let hexFlag = Range(match.range(at: 1), in: result),
                      let digits = Range(match.range(at: 2), in: result) else { continue }
                let radix = result[hexFlag].isEmpty ? 10 : 16
                guard let value = UInt32(result[digits], radix: radix),
                      let scalar = Unicode.Scalar(value) else { continue }
                result.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        let named: [(String, String)] = [
            ("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&"),
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}
