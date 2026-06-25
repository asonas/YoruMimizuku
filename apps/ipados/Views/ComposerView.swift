import PhotosUI
import SwiftUI
import YoruMimizukuKit

struct ComposerView: View {
    @ObservedObject var model: ComposerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedVideo: [PhotosPickerItem] = []
    @State private var videoPoster: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                editorSection
                quoteSection
                imagesSection
                videoSection
                errorSection
            }
            .navigationTitle(model.replyParentURI == nil ? "投稿" : "返信")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await model.submit() }
                    } label: {
                        if model.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Post")
                        }
                    }
                    .disabled(!model.canSubmit)
                }
            }
            .onChange(of: selectedItems) { _, items in
                Task { await appendImages(from: items) }
            }
            .onChange(of: selectedVideo) { _, items in
                Task { await attachVideo(from: items) }
            }
        }
    }

    @ViewBuilder private var editorSection: some View {
        Section {
            TextEditor(text: $model.text)
                .frame(minHeight: 160)
            HStack {
                Text("\(model.remaining)")
                    .foregroundStyle(model.remaining < 0 ? .red : .secondary)
                Spacer()
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: ComposerViewModel.maxImages - model.images.count,
                    matching: .images
                ) {
                    Label("画像を追加", systemImage: "photo.badge.plus")
                }
                .disabled(!model.canAddImage)
                // A video is exclusive with images; one at a time.
                PhotosPicker(selection: $selectedVideo, maxSelectionCount: 1, matching: .videos) {
                    Label("動画を追加", systemImage: "video.badge.plus")
                }
                .disabled(!model.canAddVideo)
            }
            if model.isSubmitting, let label = phaseLabel {
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var quoteSection: some View {
        if let quoted = model.quotedPost {
            Section("引用") {
                Text(quoted.authorDisplayName).font(.headline)
                Text(quoted.body).foregroundStyle(.secondary).lineLimit(4)
            }
        }
    }

    @ViewBuilder private var imagesSection: some View {
        if !model.images.isEmpty {
            Section("画像") {
                ForEach($model.images) { $image in
                    VStack(alignment: .leading) {
                        HStack {
                            Text("添付画像")
                            Spacer()
                            Button("削除", role: .destructive) {
                                model.images.removeAll { $0.id == image.id }
                            }
                        }
                        TextField("Alt text", text: $image.alt)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    @ViewBuilder private var videoSection: some View {
        if model.video != nil {
            Section("動画") {
                HStack(alignment: .top, spacing: 12) {
                    videoThumbnail
                        .frame(width: 96, height: 72).clipped().cornerRadius(8)
                    VStack(alignment: .leading) {
                        Button("削除", role: .destructive) {
                            model.video = nil
                            videoPoster = nil
                        }
                        TextField("Alt text", text: videoAltBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    @ViewBuilder private var videoThumbnail: some View {
        ZStack {
            if let videoPoster {
                Image(uiImage: videoPoster).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.2))
            }
            Image(systemName: "play.circle.fill")
                .foregroundStyle(.white)
                .shadow(radius: 2)
        }
    }

    @ViewBuilder private var errorSection: some View {
        if let message = model.errorMessage {
            Section { Text(message).foregroundStyle(.red) }
        }
    }

    /// Status line shown while a video post is in flight (upload + processing can
    /// take a while, unlike an image post).
    private var phaseLabel: String? {
        switch model.submitPhase {
        case .uploadingVideo: return "動画をアップロード中…"
        case .processingVideo: return "動画を変換中…"
        case .posting, .idle: return nil
        }
    }

    /// Binds the alt-text field to the optional video's `alt`.
    private var videoAltBinding: Binding<String> {
        Binding(get: { model.video?.alt ?? "" }, set: { model.video?.alt = $0 })
    }

    private func appendImages(from items: [PhotosPickerItem]) async {
        defer { selectedItems = [] }
        for item in items where model.canAddImage {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let encoded = ImageEncoder.jpegData(from: data) else { continue }
            model.images.append(ComposeImage(data: encoded, mimeType: "image/jpeg"))
        }
    }

    private func attachVideo(from items: [PhotosPickerItem]) async {
        defer { selectedVideo = [] }
        guard model.canAddVideo, let item = items.first else { return }
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self),
              let loaded = await VideoAttachment.load(url: movie.url) else { return }
        model.video = loaded.video
        videoPoster = loaded.poster
    }
}
