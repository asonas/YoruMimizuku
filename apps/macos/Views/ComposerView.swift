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
                // Use the app font family (Hiragino Sans) at a slightly larger size
                // than the system default so the editor reads as clearly as the rest
                // of the UI rather than the smaller raw system body face.
                .font(.appSize(15))
                .lineSpacing(2)
                // TextEditor (NSTextView) insets its text by the default 5pt
                // lineFragmentPadding, so without this its first character sits
                // 5pt right of the header / preview / footer. Pull it back so the
                // body text is flush-left with the rest of the sheet.
                .padding(.leading, -5)
            if let parent = model.replyParent {
                replyPreview(parent)
            }
            if let quoted = model.quotedPost {
                quotePreview(quoted)
            }
            if !model.images.isEmpty {
                imageStrip
            }
            Divider()
            composerFooter
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(width: 460)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.png, .jpeg, .gif, .webP, .heic],
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
        .background { submitShortcuts }
    }

    private var composerFooter: some View {
        HStack {
            Button { importing = true } label: { Image(systemName: "photo.badge.plus") }
                .disabled(!model.canAddImage)
                .help("クリック、または画像をドラッグ&ドロップで添付")
            Spacer()
            Text("\(model.remaining)")
                .font(.callout).monospacedDigit()
                .foregroundStyle(model.remaining < 0 ? Color.red : theme.tertiaryText)
            Button { submitIfPossible() } label: {
                if model.isSubmitting {
                    ProgressView().controlSize(.small)
                        .frame(minWidth: 44)
                } else {
                    Text("Post")
                        .frame(minWidth: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSubmit)
        }
    }

    private func replyPreview(_ post: PostDisplay) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RemoteImage(url: post.avatarURL, maxPointSize: 28) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    theme.avatarPlaceholder
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(post.authorDisplayName.isEmpty ? post.authorHandle : post.authorDisplayName)
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text("@\(post.authorHandle)")
                        .font(.app(.caption2))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                }
                Text(post.body)
                    .font(.app(.caption))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
            }
        }
        .allowsHitTesting(false)
        .padding(8)
        .background(theme.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.hairline, lineWidth: 1))
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

    private var submitShortcuts: some View {
        ZStack {
            Button("") { submitIfPossible() }
                .keyboardShortcut(.return, modifiers: [.command])
            Button("") { submitIfPossible() }
                .keyboardShortcut(.return, modifiers: [.control])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func submitIfPossible() {
        guard model.canSubmit else { return }
        Task { await model.submit() }
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
