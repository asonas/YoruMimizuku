import SwiftUI

/// Full-window overlay that shows a post image at full size. Dismisses on Esc
/// (`onExitCommand` plus a hidden cancel-action button for reliability), on a
/// background tap, or via the close button.
struct ImageLightboxView: View {
    let url: URL
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else if phase.error != nil {
                    Label("画像を読み込めませんでした", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.white)
                } else {
                    ProgressView().controlSize(.large).tint(.white)
                }
            }
            .padding(40)

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
                Spacer()
            }
        }
        .onExitCommand { onClose() }
        .transition(.opacity)
    }
}
