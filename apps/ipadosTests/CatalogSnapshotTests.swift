import XCTest
import SwiftUI
import UIKit
import SnapshotTesting
import YoruMimizukuKit

/// Renders every iPad catalog variant at a fixed width and compares against the
/// recorded reference PNGs. perceptualPrecision absorbs GPU/AA noise while still
/// catching layout shifts.
///
/// SIMULATOR PIN (record environment, decided 2026-07-03):
/// **iPad Pro 13-inch (M5) / iOS 26.5** simulator.
/// The reference PNGs were recorded on this exact simulator. iOS renders at the
/// device's display scale (2x here), so a different iPad model or OS version will
/// produce different bitmaps and fail the comparison. Run with:
/// `-destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'`.
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
        // first committed frame already carries the bitmap — the determinism path
        // the spec anticipated when runloop pumping proved insufficient.
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
        let sandbox = UserDefaults(suiteName: "as.ason.YoruMimizukuPad.snapshot-tests")!
        defer { UserDefaults.standard.removePersistentDomain(forName: "as.ason.YoruMimizukuPad.snapshot-tests") }
        let theme = ThemeStore(defaults: sandbox)
        theme.reset()
        let display = DisplaySettingsStore(defaults: sandbox)

        for variant in CatalogVariant.allCases where variant.platforms.contains(.iPadOS) {
            guard let view = CatalogRegistry.view(for: variant, width: 560) else { continue }
            let host = UIHostingController(
                rootView: view
                    .environment(\.catalogPreloadedImages, preloaded)
                    .environmentObject(theme)
                    .environmentObject(display)
                    .frame(width: 560)
                    .fixedSize(horizontal: false, vertical: true))
            host.view.backgroundColor = .clear

            // Size the host to the SwiftUI content's natural height at width 560,
            // mirroring the macOS NSHostingView fittingSize approach.
            let target = host.sizeThatFits(in: CGSize(width: 560, height: UIView.layoutFittingCompressedSize.height))
            host.view.frame = CGRect(x: 0, y: 0, width: 560, height: target.height)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()

            assertSnapshot(
                of: host.view,
                as: .image(perceptualPrecision: 0.98),
                named: variant.rawValue)
        }
    }
}
