import SwiftUI
import YoruMimizukuKit

/// An external-link preview rendered inside a post row, styled after X's full
/// large link card: a wide 1.91:1 hero image on top and, inside the same
/// bordered container, the page title in bold, the description in grey, and a
/// small host line. Links without a thumbnail render the same text section
/// alone. Sits between the post body / images and the action bar.
struct LinkCardView: View {
    let card: LinkCard
    let density: DisplayDensity
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.openURL) private var openURL

    private var maxWidth: CGFloat { density == .compact ? 320 : 440 }
    /// X's summary_large_image proportion (1200x628).
    private static let heroAspectRatio: CGFloat = 1.91

    var body: some View {
        Button {
            openURL(card.url)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let thumbURL = card.thumbURL {
                    heroImage(thumbURL)
                    Divider().overlay(theme.hairline)
                }
                textSection
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(card.url.absoluteString)
        .accessibilityLabel("リンク: \(card.title)")
    }

    /// The cover-cropped hero image filling the card's top; the container clips
    /// it to the card's rounded corners.
    private func heroImage(_ url: URL) -> some View {
        RemoteImage(url: url, maxPointSize: maxWidth) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                theme.surface.overlay(
                    Image(systemName: "globe").foregroundStyle(theme.tertiaryText)
                )
            }
        }
        .aspectRatio(Self.heroAspectRatio, contentMode: .fit)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .clipped()
    }

    /// Title, description, and host under the image (or alone for links without
    /// a thumbnail), mirroring X's card text block.
    private var textSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.title)
                .font(.app(density == .compact ? .caption : .subheadline, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if density == .comfortable, !card.description.isEmpty {
                Text(card.description)
                    .font(.app(.caption))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            if let host = card.host {
                Label(host, systemImage: "link")
                    .font(.app(.caption2))
                    .foregroundStyle(theme.tertiaryText)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, density == .compact ? 8 : 10)
        .padding(.vertical, density == .compact ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders a `LinkCardView` for a bare URL by fetching its OGP metadata on
/// first appearance. Shows nothing while loading and stays empty when the page
/// yields no usable metadata, so rows without previews keep their tight layout.
struct LazyLinkCardView: View {
    let url: URL
    let density: DisplayDensity
    /// Outer nil: not resolved yet. Inner nil: resolved to "no card".
    @State private var resolved: LinkCard??

    var body: some View {
        ZStack {
            if case let .some(.some(card)) = resolved {
                LinkCardView(card: card, density: density)
            }
        }
        .task(id: url) {
            guard resolved == nil else { return }
            resolved = .some(await LinkPreviews.shared.preview(for: url))
        }
    }
}

/// Process-wide OGP preview loader so every row shares one per-URL cache.
enum LinkPreviews {
    static let shared = LinkPreviewLoader(fetcher: URLSessionHTMLFetcher())
}

/// Live `HTMLFetching`: a plain GET with a browser-ish Accept header, capped
/// response size, and tolerant text decoding. Only http(s) URLs and HTML
/// responses are accepted — everything else throws and the loader caches the
/// miss.
struct URLSessionHTMLFetcher: HTMLFetching {
    func fetchHTML(from url: URL) async throws -> String {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw URLError(.unsupportedURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if let mime = http.mimeType, !mime.localizedCaseInsensitiveContains("html") {
            throw URLError(.cannotDecodeContentData)
        }
        // The OGP tags live in <head>; 1MB covers any sane page head while
        // keeping a huge document from ballooning memory.
        let capped = data.prefix(1_000_000)
        if let name = http.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                if let text = String(data: capped, encoding: encoding) { return text }
            }
        }
        return String(decoding: capped, as: UTF8.self)
    }

    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "YoruMimizuku/\(version) (+https://tangled.org/asonas.tngl.sh/YoruMimizuku)"
    }()
}
