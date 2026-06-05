import SwiftUI
import UniformTypeIdentifiers
import YoruMimizukuKit

/// The composer sheet: a multiline editor with a grapheme budget, up to four image
/// thumbnails with alt-text fields, and a Post button gated on `canSubmit`.
struct ComposerView: View {
    @ObservedObject var model: ComposerViewModel
    @EnvironmentObject private var theme: ThemeStore
    var onClose: () -> Void

    @State private var importing = false
    @State private var isDropTargeted = false

    private var headerTitle: String {
        if model.quotedPost != nil { return "引用投稿" }
        return model.replyParentURI == nil ? "新規投稿" : "返信"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(headerTitle)
                    .font(.headline)
                Spacer()
                Button("キャンセル") { onClose() }
            }
            TextEditor(text: $model.text)
                .frame(minHeight: 120)
                .font(.body)
            if let quoted = model.quotedPost {
                quotePreview(quoted)
            }
            if !model.images.isEmpty {
                imageStrip
            }
            HStack {
                Button { importing = true } label: { Image(systemName: "photo.badge.plus") }
                    .disabled(!model.canAddImage)
                    .help("クリック、または画像をドラッグ&ドロップで添付")
                Spacer()
                Text("\(model.remaining)")
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(model.remaining < 0 ? Color.red : theme.tertiaryText)
                Button("Post") { Task { await model.submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSubmit)
            }
            if model.isSubmitting { ProgressView().controlSize(.small) }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(width: 460)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg],
                      allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    /// Read-only preview of the post being quoted, shown inside the composer so the
    /// author sees what they are quoting. Hit testing is disabled so it cannot steal
    /// taps from the editor.
    private func quotePreview(_ post: PostDisplay) -> some View {
        PostRowView(post: post, density: .compact, now: Date(), showReplyMarker: false)
            .allowsHitTesting(false)
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 10).strokeBorder(theme.hairline, lineWidth: 1)
            )
    }

    private var imageStrip: some View {
        VStack(spacing: 8) {
            ForEach($model.images) { $image in
                HStack(alignment: .top, spacing: 8) {
                    if let nsImage = NSImage(data: image.data) {
                        Image(nsImage: nsImage).resizable().scaledToFill()
                            .frame(width: 56, height: 56).clipped().cornerRadius(6)
                    }
                    TextField("alt text", text: $image.alt)
                    Button { model.images.removeAll { $0.id == image.id } } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else { return }
        for url in urls where model.canAddImage {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let encoded = ImageEncoder.encodeForUpload(url: url) else { continue }
            model.images.append(ComposeImage(data: encoded.data, mimeType: encoded.mimeType))
        }
    }

    /// Accept images dropped onto the sheet. Finder files arrive as file URLs (kept
    /// as-is when small); images dragged from a browser or other app arrive as raw
    /// data. Each provider's bytes are encoded off the main actor, then appended on
    /// the main actor while there is still room (`canAddImage`).
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let model = self.model
        @Sendable func append(_ encoded: (data: Data, mimeType: String)?) {
            guard let encoded else { return }
            Task { @MainActor in
                guard model.canAddImage else { return }
                model.images.append(ComposeImage(data: encoded.data, mimeType: encoded.mimeType))
            }
        }

        var accepted = false
        for provider in providers {
            // Finder image files conform to file-url (and also to image); browser drags
            // expose a web url plus raw image data. Check file-url specifically so a web
            // url doesn't shadow the image-data path below.
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    append(ImageEncoder.encodeForUpload(url: url))
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    append(ImageEncoder.encodeForUpload(data: data))
                }
            }
        }
        return accepted
    }
}
