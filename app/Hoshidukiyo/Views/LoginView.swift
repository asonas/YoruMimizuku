import SwiftUI
import HoshidukiyoKit

/// The login screen: handle input and a sign-in button bound to `LoginViewModel`.
struct LoginView: View {
    @ObservedObject var model: LoginViewModel
    var onAuthenticated: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Hoshidukiyo").font(.title).bold().foregroundStyle(Theme.primaryText)
            Text("Bluesky にログイン").font(.callout).foregroundStyle(Theme.secondaryText)

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
            .disabled(!model.canSubmit)

            if case let .failed(message) = model.state {
                Text(message).font(.caption).foregroundStyle(.red).frame(width: 280)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
