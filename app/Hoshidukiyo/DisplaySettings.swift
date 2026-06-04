import SwiftUI
import HoshidukiyoKit

/// Holds user-facing display preferences (currently the timeline `DisplayDensity`)
/// and persists them so the choice survives launches. Shared via `environmentObject`
/// so the settings screen and the timeline read and write the same value.
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
