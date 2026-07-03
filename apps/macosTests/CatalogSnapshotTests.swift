import XCTest
import SwiftUI
import SnapshotTesting
import YoruMimizukuKit

/// Renders every macOS catalog variant at a fixed width and compares against
/// the recorded reference PNGs. perceptualPrecision absorbs GPU/AA noise while
/// still catching layout shifts like the 2026-07-03 grid overlap.
///
/// No `@testable import YoruMimizuku`: this target lists the production files it
/// exercises directly in `project.yml` sources, so `CatalogRegistry`,
/// `RemoteImage`, and `ImageDownsampler` are compiled into the test bundle.
final class CatalogSnapshotTests: XCTestCase {
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
        let theme = ThemeStore(defaults: sandbox)
        theme.reset()
        let display = DisplaySettingsStore(defaults: sandbox)

        for variant in CatalogVariant.allCases where variant.platforms.contains(.macOS) {
            guard let view = CatalogRegistry.view(for: variant, width: 560) else { continue }
            let host = NSHostingView(
                rootView: view
                    .environment(\.catalogPreloadedImages, preloaded)
                    .environmentObject(theme)
                    .environmentObject(display)
                    .frame(width: 560)
                    .fixedSize(horizontal: false, vertical: true))
            host.frame = NSRect(x: 0, y: 0, width: 560, height: host.fittingSize.height)

            // Give RemoteImage's .task a few runloop turns to publish the cached
            // image before the snapshot is captured.
            Self.pumpRunLoop(turns: 5, each: 0.05)

            assertSnapshot(
                of: host,
                as: .image(perceptualPrecision: 0.98),
                named: variant.rawValue)
        }
    }

    /// Pumps the main runloop synchronously. `RunLoop.run(until:)` is annotated
    /// `noasync`, so it lives here in a synchronous helper and is called from the
    /// async test body.
    @MainActor
    private static func pumpRunLoop(turns: Int, each seconds: TimeInterval) {
        for _ in 0..<turns {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }
    }
}
