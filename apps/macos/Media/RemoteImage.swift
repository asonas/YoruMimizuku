import SwiftUI
import CoreGraphics

/// Loading state for `RemoteImage`, mirroring `AsyncImage`'s phases so call sites
/// read the same way.
enum RemoteImagePhase {
    case empty
    case success(Image)
    case failure
}

#if DEBUG
/// DEBUG-only table of already-decoded images keyed by their URL that
/// `RemoteImage` consults *synchronously* before its async `.task`.
///
/// The snapshot suite injects this: `RemoteImage` normally decodes off the main
/// actor and publishes the result a runloop turn later, so a view captured
/// immediately shows the spinner placeholder — a race that made recorded PNGs
/// nondeterministic. With this table populated, the first committed frame already
/// carries the fixture bitmap, so snapshots are stable without runloop pumping.
/// Empty in production, so `RemoteImage` behaves exactly as before.
struct CatalogPreloadedImagesKey: EnvironmentKey {
    static let defaultValue: [URL: CGImage] = [:]
}

extension EnvironmentValues {
    var catalogPreloadedImages: [URL: CGImage] {
        get { self[CatalogPreloadedImagesKey.self] }
        set { self[CatalogPreloadedImagesKey.self] = newValue }
    }
}
#endif

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

    #if DEBUG
    @Environment(\.catalogPreloadedImages) private var preloadedImages
    #endif

    private struct LoadKey: Equatable { let url: URL?; let scale: CGFloat }

    var body: some View {
        content(resolvedPhase)
            .task(id: LoadKey(url: url, scale: displayScale)) { await load() }
    }

    /// The phase to render. Normally this is the async-loaded `phase`; in DEBUG,
    /// while still `.empty`, a preloaded fixture image (if any) is served
    /// synchronously so the very first frame is stable for snapshot tests.
    private var resolvedPhase: RemoteImagePhase {
        #if DEBUG
        if case .empty = phase, let url, let cgImage = preloadedImages[url] {
            return .success(Image(decorative: cgImage, scale: displayScale))
        }
        #endif
        return phase
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
