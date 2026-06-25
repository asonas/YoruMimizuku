import SwiftUI
import YoruMimizukuKit

/// The login screen: the YoruMimizuku mark, a handle field, and a sign-in button
/// bound to `LoginViewModel`. Themed to match the rest of the app (canvas
/// background, `.app(...)` fonts, palette colors) rather than system defaults.
struct LoginView: View {
    @ObservedObject var model: LoginViewModel
    @EnvironmentObject private var theme: ThemeStore
    let onAuthenticated: (String) -> Void

    private var isAuthenticating: Bool { model.state == .authenticating }

    var body: some View {
        VStack(spacing: 28) {
            header
            field
            submitButton
            failureMessage
        }
        .frame(maxWidth: 360)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.canvas)
        .onChange(of: model.state) { _, state in
            if case let .authenticated(did) = state {
                onAuthenticated(did)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image("AppMark")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(theme.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            VStack(spacing: 6) {
                Text("YoruMimizuku")
                    .font(.appSize(30, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text("Bluesky にログイン")
                    .font(.app(.callout))
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private var field: some View {
        TextField("handle（例: alice.bsky.social）", text: $model.handle)
            .font(.app(.body))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1)
            )
            .disabled(isAuthenticating)
            .onSubmit { Task { await model.submit() } }
    }

    private var submitButton: some View {
        Button {
            Task { await model.submit() }
        } label: {
            Group {
                if isAuthenticating {
                    ProgressView().tint(.white)
                } else {
                    Text("ログイン").font(.app(.body, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(.white)
            .background(
                theme.accent.opacity(model.canSubmit ? 1 : 0.4),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!model.canSubmit)
    }

    @ViewBuilder
    private var failureMessage: some View {
        if case let .failed(message) = model.state {
            Text(message)
                .font(.app(.caption))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }
}
