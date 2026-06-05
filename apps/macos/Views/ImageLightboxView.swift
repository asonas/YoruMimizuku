import SwiftUI
import YoruMimizukuKit

/// Full-window overlay that shows a post's images at full size. When a post has
/// several images the left/right arrow keys page between them (clamped at both
/// ends — no wrap-around), and on-screen chevrons offer the same. Dismisses on
/// Esc (`onExitCommand` plus a hidden cancel-action button for reliability), on
/// a background tap, or via the close button.
struct ImageLightboxView: View {
    let onClose: () -> Void

    @State private var gallery: ImageGallery

    init(gallery: ImageGallery, onClose: @escaping () -> Void) {
        _gallery = State(initialValue: gallery)
        self.onClose = onClose
    }

    private var hasMultiple: Bool { gallery.count > 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            image
                .padding(.horizontal, hasMultiple ? 88 : 40)
                .padding(.vertical, 40)

            if hasMultiple {
                navigationChevrons
                counter
            }

            closeButton
            arrowKeyShortcuts
        }
        .onExitCommand { onClose() }
        .transition(.opacity)
    }

    @ViewBuilder
    private var image: some View {
        if let url = gallery.current {
            RemoteImage(url: url, maxPointSize: 1600) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    Label("画像を読み込めませんでした", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.white)
                case .empty:
                    ProgressView().controlSize(.large).tint(.white)
                }
            }
            // Re-create the image view per index so paging swaps the picture
            // instead of reusing the previous one's loaded state.
            .id(gallery.index)
        }
    }

    private var navigationChevrons: some View {
        HStack {
            chevron(systemImage: "chevron.left", enabled: gallery.canGoPrevious) { gallery.goPrevious() }
            Spacer()
            chevron(systemImage: "chevron.right", enabled: gallery.canGoNext) { gallery.goNext() }
        }
        .padding(.horizontal, 20)
    }

    private func chevron(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.85 : 0.2))
                .padding(16)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var counter: some View {
        VStack {
            Spacer()
            Text("\(gallery.index + 1) / \(gallery.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.4), in: Capsule())
                .padding(.bottom, 24)
        }
    }

    private var closeButton: some View {
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

    /// Zero-size buttons that bind the arrow keys to paging. Disabled at the ends
    /// so the shortcut is a no-op there (matching the non-looping requirement).
    private var arrowKeyShortcuts: some View {
        ZStack {
            Button("") { gallery.goPrevious() }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!gallery.canGoPrevious)
            Button("") { gallery.goNext() }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!gallery.canGoNext)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
