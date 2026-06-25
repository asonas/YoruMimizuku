import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A snapshot of the attachable image payloads on a pasteboard, captured on the
/// main thread. Value-type and `Sendable` so it can be handed to the encoder.
/// File URLs take precedence: a Finder item vends both a file URL and an
/// `NSImage`, and we prefer the original file bytes, so raw image data is read
/// only when there are no image files (a screenshot or a browser image copy).
struct PasteboardImageSnapshot: ComposerImageSource, Sendable {
    let fileURLs: [URL]
    let dataItems: [Data]

    func imageFileURLs() -> [URL] { fileURLs }
    func imageDataItems() -> [Data] { dataItems }

    var hasImages: Bool { !fileURLs.isEmpty || !dataItems.isEmpty }

    init(_ pasteboard: NSPasteboard) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: Self.imageURLOptions) as? [URL]) ?? []
        fileURLs = urls
        if urls.isEmpty {
            let images = (pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]) ?? []
            dataItems = images.compactMap { $0.tiffRepresentation }
        } else {
            dataItems = []
        }
    }

    /// Cheap check for whether `pasteboard` carries images, used to drive the drop
    /// highlight without materializing (and re-encoding) the payload.
    static func pasteboardHasImages(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: imageURLOptions)
            || pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    private static var imageURLOptions: [NSPasteboard.ReadingOptionKey: Any] {
        [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]
    }
}

/// An `NSTextView` that intercepts image pastes and drops so they become post
/// attachments instead of inserted file-path text. Plain text falls through to
/// the default behavior.
final class AttachingTextView: NSTextView {
    var onAttachImages: ((PasteboardImageSnapshot) -> Void)?
    var onDragTargeted: ((Bool) -> Void)?

    override func paste(_ sender: Any?) {
        let snapshot = PasteboardImageSnapshot(NSPasteboard.general)
        if snapshot.hasImages {
            onAttachImages?(snapshot)
            return
        }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if PasteboardImageSnapshot.pasteboardHasImages(sender.draggingPasteboard) {
            onDragTargeted?(true)
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if PasteboardImageSnapshot.pasteboardHasImages(sender.draggingPasteboard) {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragTargeted?(false)
        super.draggingExited(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragTargeted?(false)
        let snapshot = PasteboardImageSnapshot(sender.draggingPasteboard)
        if snapshot.hasImages {
            onAttachImages?(snapshot)
            return true
        }
        return super.performDragOperation(sender)
    }
}

/// SwiftUI wrapper around `AttachingTextView` in a scroll view, used as the
/// composer body editor in place of `TextEditor` so image paste / drop can be
/// intercepted. Mirrors the editor's font and flush-left layout.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isDropTargeted: Bool
    var font: NSFont
    var onAttachImages: (PasteboardImageSnapshot) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = AttachingTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = font
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.onAttachImages = { [weak coordinator = context.coordinator] snapshot in
            coordinator?.parent.onAttachImages(snapshot)
        }
        textView.onDragTargeted = { [weak coordinator = context.coordinator] targeted in
            coordinator?.parent.isDropTargeted = targeted
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? AttachingTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if textView.font != font {
            textView.font = font
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView

        init(_ parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
