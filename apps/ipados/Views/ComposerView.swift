import PhotosUI
import SwiftUI
import YoruMimizukuKit

struct ComposerView: View {
    @ObservedObject var model: ComposerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            Form {
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
                    }
                }

                if let quoted = model.quotedPost {
                    Section("引用") {
                        Text(quoted.authorDisplayName)
                            .font(.headline)
                        Text(quoted.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }

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

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
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
        }
    }

    private func appendImages(from items: [PhotosPickerItem]) async {
        defer { selectedItems = [] }
        for item in items where model.canAddImage {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let encoded = ImageEncoder.jpegData(from: data) else { continue }
            model.images.append(ComposeImage(data: encoded, mimeType: "image/jpeg"))
        }
    }
}
