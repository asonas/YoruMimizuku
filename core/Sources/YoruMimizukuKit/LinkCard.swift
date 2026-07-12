import Foundation
import BlueskyCore

/// An external-link preview shown inside a post row, in the style of a web embed
/// card: thumbnail, title, description, and the link's host. Built either from
/// the post's `app.bsky.embed.external#view` (the posting client's OGP capture)
/// or from OGP metadata fetched on demand for a bare URL in the body.
public struct LinkCard: Equatable, Sendable {
    public let url: URL
    public let title: String
    public let description: String
    public let thumbURL: URL?

    /// The host shown as the card's source line, with a leading "www." dropped
    /// ("www.ableton.com" reads better as "ableton.com").
    public var host: String? {
        url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
    }

    public init(url: URL, title: String, description: String, thumbURL: URL? = nil) {
        self.url = url
        self.title = title
        self.description = description
        self.thumbURL = thumbURL
    }
}

extension LinkCard {
    /// Map the hydrated external embed into a card; nil when its `uri` is not a
    /// parseable http(s) URL. A non-web scheme (file://, custom app scheme) from a
    /// hostile post produces no card, so tapping it can never hand that URL to the
    /// system opener.
    public init?(_ external: EmbedExternal) {
        guard let url = URL(string: external.uri), url.isWebLink else { return nil }
        self.init(
            url: url,
            title: external.title,
            description: external.description,
            thumbURL: external.thumb.flatMap(URL.init(string:))
        )
    }
}
