import SwiftUI
import YoruMimizukuKit

/// The poster frame of a video embed with a centered play badge. Playback is
/// not inline in v1 — the host decides what activating the poster does
/// (typically opening the post in the browser).
struct VideoPosterView: View {
    let video: PostVideo
    let maxWidth: CGFloat
    var onTap: (() -> Void)?

    @EnvironmentObject private var theme: ThemeStore

    /// 16:9 covers most Bluesky videos whose embed omits the aspect ratio.
    private var aspectRatio: CGFloat { CGFloat(video.aspectRatio ?? 16.0 / 9.0) }

    var body: some View {
        if let onTap {
            Button(action: onTap) { poster }
                .buttonStyle(.plain)
                .help("ブラウザで動画を開く")
        } else {
            poster
        }
    }

    private var poster: some View {
        RemoteImage(url: video.thumbURL, maxPointSize: maxWidth) { phase in
            if case let .success(image) = phase {
                image.resizable().scaledToFill()
            } else {
                theme.surface
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .clipped()
        .overlay(playBadge)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(video.alt?.isEmpty == false ? "動画: \(video.alt ?? "")" : "動画")
    }

    private var playBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .padding(14)
            .background(Circle().fill(.black.opacity(0.55)))
    }
}
