import SwiftUI

/// Warm-stone dark theme for the Yorufukurou-style UI. Anchored on the
/// high-contrast pair #44403c (background) / #fafaf9 (text); other tones are
/// drawn from the Tailwind "stone" scale to keep the palette coherent.
enum Theme {
    /// #44403c (stone-700) — main timeline background.
    static let background = Color(red: 0.267, green: 0.251, blue: 0.235)
    /// #57534e (stone-600) — bars, chips, and the composer, one step lighter.
    static let surface = Color(red: 0.341, green: 0.325, blue: 0.306)
    /// #2563eb (blue-600) — links, the active tab, and the account marker.
    static let accent = Color(red: 0.145, green: 0.388, blue: 0.922)
    /// #fafaf9 (stone-50) — primary text, ~10:1 contrast on `background`.
    static let primaryText = Color(red: 0.980, green: 0.980, blue: 0.976)
    /// #d6d3d1 (stone-300) — secondary text, ~7:1 contrast on `background`.
    static let secondaryText = Color(red: 0.839, green: 0.827, blue: 0.820)
    /// #78716c (stone-500) — neutral fill shown until an avatar image loads.
    static let avatarPlaceholder = Color(red: 0.471, green: 0.443, blue: 0.420)
    static let divider = Color.white.opacity(0.12)
}
