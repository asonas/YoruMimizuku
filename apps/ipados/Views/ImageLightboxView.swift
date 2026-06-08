import SwiftUI
import YoruMimizukuKit

struct ImageLightboxView: View {
    @State private var gallery: ImageGallery
    let onClose: () -> Void

    init(gallery: ImageGallery, onClose: @escaping () -> Void) {
        _gallery = State(initialValue: gallery)
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            if let current = gallery.current {
                AsyncImage(url: current) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.7))
                    default:
                        ProgressView()
                            .tint(.white)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Button {
                    gallery.goPrevious()
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 42))
                }
                .disabled(!gallery.canGoPrevious)

                Spacer()

                Button {
                    gallery.goNext()
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 42))
                }
                .disabled(!gallery.canGoNext)
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding()
            }
        }
    }
}
