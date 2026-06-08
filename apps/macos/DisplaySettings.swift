import SwiftUI
import AppKit
import YoruMimizukuKit

/// Holds the user's chosen UI font family and persists it. Keeps `AppTypography`
/// (read by the `Font.app(...)` helpers) in sync so the whole UI re-renders with
/// the new family when the selection changes. Shared via `environmentObject`; the
/// app's root holds it as a `@StateObject`, so publishing a change re-renders the
/// entire view tree and every `.font(.app(...))` picks up the new family.
@MainActor
final class FontSettingsStore: ObservableObject {
    @Published var family: String {
        didSet {
            AppTypography.family = family
            defaults.set(family, forKey: Self.familyKey)
        }
    }

    /// The body text point size that drives the whole UI (see `AppTypography.baseSize`).
    @Published var baseSize: Double {
        didSet {
            AppTypography.baseSize = CGFloat(baseSize)
            defaults.set(baseSize, forKey: Self.baseSizeKey)
        }
    }

    private let defaults: UserDefaults
    private static let familyKey = "display.fontFamily"
    private static let baseSizeKey = "display.fontBaseSize"

    /// All font families installed on the system, sorted for the picker. Computed
    /// lazily: enumerating and sorting every installed family is expensive (it was
    /// a top main-thread allocation in Time Profiler), and only the settings picker
    /// ever needs it — `init` must stay cheap because the app root reconstructs
    /// this store's `@StateObject` initializer on every re-render.
    lazy var availableFamilies: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Fall back to the default if nothing is stored or the stored font is no
        // longer installed, so a missing font never leaves the UI unrendered. The
        // common case (nothing stored) short-circuits before any font lookup; a
        // stored family is validated with a single-family query, never the full
        // enumeration that `availableFamilies` performs.
        let stored = defaults.string(forKey: Self.familyKey)
        let resolved = stored.flatMap { Self.isInstalled($0) ? $0 : nil }
            ?? AppTypography.systemDefaultFamily
        self.family = resolved
        AppTypography.family = resolved

        let storedSize = defaults.object(forKey: Self.baseSizeKey) as? Double
        let resolvedSize = storedSize.map {
            min(max($0, Double(AppTypography.minBaseSize)), Double(AppTypography.maxBaseSize))
        } ?? Double(AppTypography.defaultBaseSize)
        self.baseSize = resolvedSize
        AppTypography.baseSize = CGFloat(resolvedSize)
    }

    /// Whether `family` is installed, via a single-family query rather than
    /// enumerating every installed family (the enumeration is deferred to
    /// `availableFamilies`).
    private static func isInstalled(_ family: String) -> Bool {
        NSFontManager.shared.availableMembers(ofFontFamily: family) != nil
    }

    /// Restore the built-in default family and size.
    func reset() {
        family = AppTypography.systemDefaultFamily
        baseSize = Double(AppTypography.defaultBaseSize)
    }

    var isDefault: Bool {
        family == AppTypography.systemDefaultFamily
            && baseSize == Double(AppTypography.defaultBaseSize)
    }
}

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
