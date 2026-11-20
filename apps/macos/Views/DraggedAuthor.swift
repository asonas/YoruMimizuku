import SwiftUI
import BlueskyCore
import YoruMimizukuKit
import UniformTypeIdentifiers

extension UTType {
    /// Declared in the app's Info.plist (`UTExportedTypeDeclarations`).
    static let yoruMimizukuAuthor = UTType(exportedAs: "as.ason.YoruMimizuku.author")
}

/// A post's author dragged by the avatar onto a sidebar list (by DID) or filter
/// (by handle, as a `from:` condition). Other apps receive the `@handle` text.
struct DraggedAuthor: Codable, Transferable {
    let did: String
    let handle: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .yoruMimizukuAuthor)
        ProxyRepresentation(exporting: { "@\($0.handle)" })
    }
}

/// Makes the avatar draggable as its post's author. A post whose URI has no
/// repo DID is left undraggable.
struct AuthorDragSource: ViewModifier {
    let post: PostDisplay

    func body(content: Content) -> some View {
        if let did = ATURI.repo(post.id) {
            content.draggable(DraggedAuthor(did: did, handle: post.authorHandle))
        } else {
            content
        }
    }
}
