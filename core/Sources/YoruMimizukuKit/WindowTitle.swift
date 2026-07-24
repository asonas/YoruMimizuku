import Foundation

/// Composes the macOS window title shown in Mission Control / the Window menu /
/// the Dock, even under `.hiddenTitleBar`.
public enum WindowTitle {
    /// "ホーム — @asonas.bsky.social"; the handle part is dropped when empty.
    public static func compose(tabTitle: String, accountHandle: String) -> String {
        let trimmed = accountHandle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return tabTitle }
        let handle = trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
        return "\(tabTitle) — \(handle)"
    }
}
