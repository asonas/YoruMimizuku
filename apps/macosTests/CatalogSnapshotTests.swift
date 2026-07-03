import XCTest
import SwiftUI
import SnapshotTesting
import YoruMimizukuKit

/// Renders every macOS catalog variant at a fixed width and compares against
/// the recorded reference PNGs. perceptualPrecision absorbs GPU/AA noise while
/// still catching layout shifts like the 2026-07-03 grid overlap.
///
/// SCALE PIN (record environment, decided 2026-07-03):
/// **The bitmap is rendered at a fixed 2x scale, independent of NSScreen.**
/// The previous implementation snapshotted an `NSHostingView` via the `.image`
/// strategy, whose bitmap scale follows the current display: the committed
/// references were @2x (1120px wide for the 560pt column), but a 4K display set
/// to a "looks like native" (1x) mode renders @1x (560px) and every PostRow
/// snapshot fails. The suite was environment-dependent and flapped whenever the
/// display configuration changed. To make it deterministic we lay out an
/// `NSHostingView` at the fixed width and draw it into an explicitly-sized
/// `NSBitmapImageRep` whose pixel dimensions are exactly 2x the point size, so
/// output is the same regardless of screen. (`ImageRenderer` was tried first but
/// deterministically dropped to 1x for the `postRowLinkCard` variant, so it could
/// not guarantee a uniform scale.) This mirrors how the iPad file pins its
/// simulator.
///
/// No `@testable import YoruMimizuku`: this target lists the production files it
/// exercises directly in `project.yml` sources, so `CatalogRegistry`,
/// `RemoteImage`, and `ImageDownsampler` are compiled into the test bundle.
final class CatalogSnapshotTests: XCTestCase {
    /// Fixed rendering scale for the recorded references. Pinned so the bitmap
    /// resolution never follows the machine's NSScreen configuration.
    private static let renderScale: CGFloat = 2.0
    /// Fixed content width, in points.
    private static let contentWidth: CGFloat = 560

    @MainActor
    func testCatalogVariants() async throws {
        // RemoteImage decodes off the main actor and publishes a runloop turn
        // later, so a view captured immediately would show the spinner
        // placeholder. Decode every fixture up front and hand RemoteImage a
        // synchronous preloaded table (a DEBUG-only environment override) so the
        // first committed frame already carries the bitmap — the determinism
        // path the spec anticipated when runloop pumping proved insufficient.
        var preloaded: [URL: CGImage] = [:]
        for name in ["sample-wide", "sample-wide2", "sample-tall"] {
            let url = CatalogFixtures.imageURL(name)
            let decoded = try await ImageDownsampler.shared.image(for: url, maxPixel: 2048)
            preloaded[url] = decoded.cgImage
        }

        // The catalog components read the palette from a ThemeStore in the
        // environment (as the in-app gallery injects it). A throwaway defaults
        // suite reset to the built-in palette keeps the recorded colors stable
        // regardless of any persisted randoma11y state on the machine.
        let sandbox = UserDefaults(suiteName: "as.ason.YoruMimizuku.snapshot-tests")!
        defer { UserDefaults.standard.removePersistentDomain(forName: "as.ason.YoruMimizuku.snapshot-tests") }
        let theme = ThemeStore(defaults: sandbox)
        theme.reset()
        let display = DisplaySettingsStore(defaults: sandbox)

        for variant in CatalogVariant.allCases where variant.platforms.contains(.macOS) {
            guard let view = CatalogRegistry.view(for: variant, width: Self.contentWidth) else { continue }
            let host = NSHostingView(
                rootView: view
                    .environment(\.catalogPreloadedImages, preloaded)
                    .environmentObject(theme)
                    .environmentObject(display)
                    .frame(width: Self.contentWidth)
                    .fixedSize(horizontal: false, vertical: true))
            host.frame = NSRect(x: 0, y: 0, width: Self.contentWidth, height: host.fittingSize.height)
            host.layoutSubtreeIfNeeded()

            guard let image = Self.pinnedScaleImage(of: host) else {
                XCTFail("Could not render bitmap for variant \(variant.rawValue)")
                continue
            }

            assertSnapshot(
                of: image,
                as: .image(perceptualPrecision: 0.98),
                named: variant.rawValue)
        }
    }

    /// Draws `view` into an `NSBitmapImageRep` whose pixel dimensions are exactly
    /// `renderScale` times the view's point size, so the captured bitmap is @2x
    /// regardless of the machine's screen backing scale. `NSView`'s own
    /// `bitmapImageRepForCachingDisplay(in:)` would pick up the current screen
    /// scale, which is precisely the environment dependency we are eliminating.
    @MainActor
    private static func pinnedScaleImage(of view: NSView) -> NSImage? {
        let pointSize = view.bounds.size
        let pixelWidth = Int((pointSize.width * renderScale).rounded())
        let pixelHeight = Int((pointSize.height * renderScale).rounded())
        guard pixelWidth > 0, pixelHeight > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0)
        else { return nil }
        // Setting the rep's point size while its pixel dimensions are 2x makes
        // `cacheDisplay` draw the view at 2x scale into the buffer.
        rep.size = pointSize
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        return image
    }
}
