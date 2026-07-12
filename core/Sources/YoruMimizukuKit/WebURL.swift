import Foundation

extension URL {
    /// True when this URL is a web link (http or https) — the only schemes the app
    /// treats as tappable / openable.
    ///
    /// atproto post content (external-embed URIs, link-facet URIs) is authored by
    /// arbitrary users, so a hostile post can carry a non-web scheme (`file://`, a
    /// custom app scheme) that, if handed to `openURL` / `NSWorkspace.open`, would
    /// escape the browser and open a local file or launch another app. The client
    /// therefore only ever renders http(s) URLs as links; everything else stays
    /// plain text. This mirrors the guard the OGP fetcher already applies, extended
    /// to the tap/open path.
    var isWebLink: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
