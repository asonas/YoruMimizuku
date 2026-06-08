import SwiftUI
import YoruMimizukuKit

struct LoginView: View {
    @ObservedObject var model: LoginViewModel
    let onAuthenticated: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
            Text("YoruMimizuku")
                .font(.largeTitle.bold())
            Text("Bluesky の handle を入力して OAuth でログインします。")
                .foregroundStyle(.secondary)
            TextField("asonas.bsky.social", text: $model.handle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)
                .onSubmit { Task { await model.submit() } }
            Button {
                Task { await model.submit() }
            } label: {
                if model.state == .authenticating {
                    ProgressView()
                } else {
                    Text("ログイン")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSubmit)

            if case let .failed(message) = model.state {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 520)
            }
        }
        .padding()
        .onChange(of: model.state) { _, state in
            if case let .authenticated(did) = state {
                onAuthenticated(did)
            }
        }
    }
}
