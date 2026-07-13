import SwiftUI
import YoruMimizukuKit

/// iPad twin of the macOS session-expiry banner. Shown above the timeline while
/// the current account awaits re-authentication.
struct SessionReauthBanner: View {
    let onReauth: () -> Void
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.accent)
            Text("セッションが期限切れです")
                .font(.app(.caption))
                .foregroundStyle(theme.primaryText)
            Spacer(minLength: 8)
            Button("再ログイン", action: onReauth)
                .font(.app(.caption))
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(alignment: .bottom) { Divider().overlay(theme.divider) }
    }
}
