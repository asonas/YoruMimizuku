import Foundation

/// Detects rich-text facets in post text using UTF-8 byte offsets (NOT character
/// offsets), mirroring the proven detection in tempest. `link` and `tag` are
/// produced complete; `mentionCandidate` carries the `@handle` range and handle
/// string for `PostService` to resolve to a DID. Mirrors the display-side
/// `RichText` decoder so composed and rendered facets stay symmetric.
public enum FacetDetector {
    public struct DetectedFacet: Equatable, Sendable {
        public let byteStart: Int
        public let byteEnd: Int
        public let feature: Feature

        public init(byteStart: Int, byteEnd: Int, feature: Feature) {
            self.byteStart = byteStart
            self.byteEnd = byteEnd
            self.feature = feature
        }
    }

    public enum Feature: Equatable, Sendable {
        case link(uri: String)
        case tag(tag: String)
        case mentionCandidate(handle: String)
    }

    /// Detect all facets and return them sorted by byte start.
    public static func detect(text: String) -> [DetectedFacet] {
        let all = detectLinks(text) + detectTags(text) + detectMentions(text)
        return all.sorted { $0.byteStart < $1.byteStart }
    }

    // Trailing characters stripped from a detected URL so a sentence's closing
    // punctuation does not become part of the link (mirrors @atproto/api).
    private static let linkTrailing = CharacterSet(charactersIn: ".,;:!?)\"']")

    static func detectLinks(_ text: String) -> [DetectedFacet] {
        var facets: [DetectedFacet] = []
        // Scan for http(s):// runs up to the next whitespace.
        guard let regex = try? NSRegularExpression(pattern: "https?://[^\\s]+") else { return [] }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var uri = ns.substring(with: match.range)
            // Strip trailing punctuation; keep a closing paren only if the URL has a matching open paren.
            while let last = uri.unicodeScalars.last, linkTrailing.contains(last) {
                if last == ")" && uri.filter({ $0 == "(" }).count > uri.filter({ $0 == ")" }).count { break }
                uri = String(uri.dropLast())
            }
            guard !uri.isEmpty else { continue }
            let uriBytes = Array(uri.utf8)
            // Locate the URL's byte range by re-finding its byte prefix from the match's UTF-16 start.
            let prefix = ns.substring(to: match.range.location)
            let byteStart = Array(prefix.utf8).count
            facets.append(DetectedFacet(byteStart: byteStart, byteEnd: byteStart + uriBytes.count,
                                        feature: .link(uri: uri)))
        }
        return facets
    }

    // A hashtag starts at text start or after whitespace, allows a fullwidth '#',
    // must contain at least one non-digit/non-punctuation character (so bare
    // "#123" is ignored), drops trailing punctuation, and is capped at 64 graphemes.
    static func detectTags(_ text: String) -> [DetectedFacet] {
        guard text.contains("#") || text.contains("＃") else { return [] }
        let pattern = "(?:^|\\s)[#＃]([^\\s#＃]*[^\\d\\s\\p{P}#＃]+[^\\s#＃]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var facets: [DetectedFacet] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let bodyRange = match.range(at: 1)
            var tag = ns.substring(with: bodyRange)
            while let last = tag.unicodeScalars.last,
                  CharacterSet.punctuationCharacters.contains(last) {
                tag = String(tag.dropLast())
            }
            guard !tag.isEmpty, tag.count <= 64 else { continue }
            // The '#' sits one UTF-16 unit before the captured body; rebuild byte offsets.
            let hashUTF16 = bodyRange.location - 1
            let prefix = ns.substring(to: hashUTF16)
            let byteStart = Array(prefix.utf8).count
            let byteEnd = byteStart + Array(("#" + tag).utf8).count
            facets.append(DetectedFacet(byteStart: byteStart, byteEnd: byteEnd, feature: .tag(tag: tag)))
        }
        return facets
    }

    // A mention starts at text start or after whitespace / '(' / '[' and matches a
    // domain-shaped handle. The byte range covers '@' + handle; PostService resolves
    // the handle to a DID and drops the facet when resolution fails.
    static func detectMentions(_ text: String) -> [DetectedFacet] {
        guard text.contains("@") else { return [] }
        let pattern = "(?:^|[\\s(\\[])@([a-zA-Z0-9._-]+\\.[a-zA-Z]{2,})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var facets: [DetectedFacet] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let handleRange = match.range(at: 1)
            let handle = ns.substring(with: handleRange)
            let atUTF16 = handleRange.location - 1
            let prefix = ns.substring(to: atUTF16)
            let byteStart = Array(prefix.utf8).count
            let byteEnd = byteStart + Array(("@" + handle).utf8).count
            facets.append(DetectedFacet(byteStart: byteStart, byteEnd: byteEnd,
                                        feature: .mentionCandidate(handle: handle)))
        }
        return facets
    }
}
