import SwiftUI
import YoruMimizukuKit

/// A small pill shown at the bottom of the screen for a transient confirmation
/// such as "リンクをコピーしました". Tapping it dismisses immediately; otherwise
/// `ToastCenter` clears it after a short delay. Mirrors the macOS `ToastView`;
/// both read the shared `ThemeStore` and `.app(...)` fonts.
struct ToastView: View {
    let message: ToastMessage

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Text(message.text)
            .font(.app(.caption))
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(theme.divider, lineWidth: 1))
            .shadow(radius: 6, y: 2)
    }
}
