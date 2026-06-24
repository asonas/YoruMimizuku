import SwiftUI
import YoruMimizukuKit

/// Holds user-facing display preferences (currently the timeline `DisplayDensity`)
/// and persists them so the choice survives launches. Shared via `environmentObject`
/// so the settings screen and the timeline read and write the same value.
///
/// The iPad target keeps only the density store; the macOS `FontSettingsStore`
/// (custom UI font family) depends on `NSFontManager` and is out of scope for the
/// iPad parity milestone (see `2026-06-24-yorumimizuku-ipados-parity-design.md` §3).
@MainActor
final class DisplaySettingsStore: ObservableObject {
    @Published var density: DisplayDensity {
        didSet { defaults.set(density.rawValue, forKey: Self.densityKey) }
    }

    private let defaults: UserDefaults
    private static let densityKey = "display.density"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.densityKey),
           let stored = DisplayDensity(rawValue: raw) {
            density = stored
        } else {
            density = .default
        }
    }
}
