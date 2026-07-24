import XCTest
import SwiftUI
import UIKit
import SnapshotTesting
import YoruMimizukuKit

/// Regression guard for the iPad notifications tab's empty state: when
/// `NotificationsViewModel` loads zero groups, `NotificationsListView` must show a
/// placeholder instead of a blank `List`. See `docs/wiki/behaviors/notifications.md`.
///
/// Follows the same environment conventions as `CatalogSnapshotTests` (theme reset
/// via a throwaway `UserDefaults` suite, fixed frame, `perceptualPrecision` to
/// absorb GPU/AA noise while still catching layout shifts).
final class NotificationsEmptySnapshotTests: XCTestCase {
    private struct EmptyLoader: NotificationsLoading {
        func loadLatest() async throws -> [NotificationGroup] { [] }
    }

    @MainActor
    func testEmptyNotificationsShowsPlaceholder() async throws {
        let sandbox = UserDefaults(suiteName: "as.ason.YoruMimizukuPad.notifications-empty-snapshot-tests")!
        defer { UserDefaults.standard.removePersistentDomain(forName: "as.ason.YoruMimizukuPad.notifications-empty-snapshot-tests") }
        let theme = ThemeStore(defaults: sandbox)
        theme.reset()

        let model = NotificationsViewModel(loader: EmptyLoader())
        await model.load()

        let view = NotificationsListView(model: model, now: Date(), onOpenAuthor: { _ in })
            .environmentObject(theme)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: 560, height: 700)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        assertSnapshot(of: host.view, as: .image(perceptualPrecision: 0.98))
    }
}
