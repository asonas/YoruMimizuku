import SwiftUI
import YoruMimizukuKit

/// The login screen: handle input and a sign-in button bound to `LoginViewModel`.
struct LoginView: View {
    @ObservedObject var model: LoginViewModel
    @EnvironmentObject private var theme: ThemeStore
    var onAuthenticated: (String) -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("✦").font(.system(size: 30)).foregroundStyle(theme.star)
                Text("YoruMimizuku")
                    .font(.appSize(34, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text("Bluesky にログイン")
                    .font(.app(.callout)).foregroundStyle(theme.secondaryText)
            }
            .padding(.bottom, 8)

            TextField("handle (例: alice.bsky.social)", text: $model.handle)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .disabled(model.state == .authenticating)

            Button {
                Task {
                    await model.submit()
                    if case let .authenticated(did) = model.state { onAuthenticated(did) }
                }
            } label: {
                if model.state == .authenticating {
                    ProgressView().controlSize(.small)
                } else {
                    Text("ログイン").bold()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .disabled(!model.canSubmit)

            if case let .failed(message) = model.state {
                Text(message).font(.app(.caption)).foregroundStyle(.red).frame(width: 280)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.canvas)
    }
}
