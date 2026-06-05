import Foundation
import BlueskyCore

/// One span of a post body, ready for display. Plain text spans carry no URL;
/// links, hashtags, and mentions carry the destination the view makes tappable.
public struct RichTextSegment: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case text
        case link
        case tag
        case mention
    }

    /// Stable position in the segment list; lets SwiftUI `ForEach` identify
    /// repeated identical spans (e.g. two plain spaces) without collisions.
    public let id: Int
    public let kind: Kind
    public let text: String
    public let url: URL?

    public init(id: Int, kind: Kind, text: String, url: URL?) {
        self.id = id
        self.kind = kind
        self.text = text
        self.url = url
    }
}

/// Turns post text plus atproto `Facet`s into display spans. Facet ranges are
/// UTF-8 byte offsets, so slicing happens on the UTF-8 view and is decoded back
/// to `String`; this keeps multibyte text (emoji, Japanese) aligned.
public enum RichText {
    public static func segments(text: String, facets: [Facet]) -> [RichTextSegment] {
        let bytes = Array(text.utf8)
        let resolved = facets
            .compactMap { facet -> (start: Int, end: Int, kind: RichTextSegment.Kind, url: URL?)? in
                guard let feature = facet.features.first(where: { Self.feature($0) != nil }),
                      let mapped = Self.feature(feature) else { return nil }
                guard facet.byteStart >= 0,
                      facet.byteEnd <= bytes.count,
                      facet.byteStart < facet.byteEnd else { return nil }
                return (facet.byteStart, facet.byteEnd, mapped.kind, mapped.url)
            }
            .sorted { $0.start < $1.start }

        var segments: [RichTextSegment] = []
        var cursor = 0
        var nextID = 0

        func appendText(from start: Int, to end: Int) {
            guard start < end else { return }
            let slice = String(decoding: bytes[start..<end], as: UTF8.self)
            segments.append(RichTextSegment(id: nextID, kind: .text, text: slice, url: nil))
            nextID += 1
        }

        for facet in resolved {
            // Skip facets that overlap one already emitted.
            guard facet.start >= cursor else { continue }
            appendText(from: cursor, to: facet.start)
            let slice = String(decoding: bytes[facet.start..<facet.end], as: UTF8.self)
            segments.append(RichTextSegment(id: nextID, kind: facet.kind, text: slice, url: facet.url))
            nextID += 1
            cursor = facet.end
        }
        appendText(from: cursor, to: bytes.count)

        return segments
    }

    private static func feature(_ feature: FacetFeature) -> (kind: RichTextSegment.Kind, url: URL?)? {
        switch feature {
        case .link(let uri):
            return (.link, URL(string: uri))
        case .tag(let tag):
            let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
            return (.tag, URL(string: "https://bsky.app/hashtag/\(encoded)"))
        case .mention(let did):
            return (.mention, URL(string: "https://bsky.app/profile/\(did)"))
        }
    }
}
