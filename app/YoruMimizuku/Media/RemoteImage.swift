import SwiftUI

/// Loading state for `RemoteImage`, mirroring `AsyncImage`'s phases so call sites
/// read the same way.
enum RemoteImagePhase {
    case empty
    case success(Image)
    case failure
}

/// A drop-in replacement for `AsyncImage` backed by `ImageDownsampler`: it loads
/// a thumbnail sized to `maxPointSize` (scaled by the display) so timeline images
/// decode small and stay cached across cell reuse. Reloads when the URL or the
/// display scale changes.
struct RemoteImage<Content: View>: View {
    let url: URL?
    /// The longest edge the image will occupy, in points. Multiplied by the
    /// display scale to pick the decode resolution.
    let maxPointSize: CGFloat
    @ViewBuilder let content: (RemoteImagePhase) -> Content

    @Environment(\.displayScale) private var displayScale
    @State private var phase: RemoteImagePhase = .empty

    private struct LoadKey: Equatable { let url: URL?; let scale: CGFloat }

    var body: some View {
        content(phase)
            .task(id: LoadKey(url: url, scale: displayScale)) { await load() }
    }

    private func load() async {
        guard let url else {
            phase = .empty
            return
        }
        let maxPixel = max(1, maxPointSize * displayScale)
        do {
            let decoded = try await ImageDownsampler.shared.image(for: url, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            phase = .success(Image(decorative: decoded.cgImage, scale: displayScale))
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failure
        }
    }
}
