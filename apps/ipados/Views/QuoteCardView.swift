import SwiftUI
import YoruMimizukuKit

/// A quoted post rendered inside a post row as a bordered card, mirroring
/// Bluesky web: a compact author line (small avatar, name, handle, relative
/// time), the quoted body, and the quoted post's own media (image thumbnails
/// or a video poster). Activating the card opens the quoted post's
/// conversation.
struct QuoteCardView: View {
    let quote: QuotedPost
    let density: DisplayDensity
    let now: Date
    var onTap: () -> Void = {}

    @EnvironmentObject private var theme: ThemeStore

    private let timeFormatter = RelativeTimeFormatter()

    private var maxWidth: CGFloat { density == .compact ? 320 : 440 }
    private var avatarSize: CGFloat { 16 }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                authorLine
                if !quote.body.isEmpty {
                    Text(quote.body)
                        .font(.app(density == .compact ? .caption : .callout))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(6)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let video = quote.video {
                    VideoPosterView(video: video, maxWidth: maxWidth - 20)
                } else if !quote.images.isEmpty {
                    thumbnails
                }
            }
            .padding(.horizontal, density == .compact ? 8 : 10)
            .padding(.vertical, density == .compact ? 6 : 8)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("@\(quote.authorHandle) の会話を開く")
        .accessibilityLabel("引用: \(quote.authorDisplayName) \(quote.body)")
    }

    private var authorLine: some View {
        HStack(spacing: 5) {
            RemoteImage(url: quote.avatarURL, maxPointSize: avatarSize) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    theme.avatarPlaceholder
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
            Text(quote.authorDisplayName)
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
            Text("@\(quote.authorHandle)")
                .font(.app(.caption2))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            Text(timeFormatter.string(for: quote.createdAt, now: now))
                .font(.app(.caption2))
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// Small fixed-size thumbnails for the quoted post's images. The quote card
    /// stays compact, so the full image grid is not reused here.
    private var thumbnails: some View {
        HStack(spacing: 4) {
            ForEach(quote.images.prefix(2)) { image in
                RemoteImage(url: image.thumbURL, maxPointSize: 72) { phase in
                    if case let .success(thumb) = phase {
                        thumb.resizable().scaledToFill()
                    } else {
                        theme.surface
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            }
        }
    }
}
