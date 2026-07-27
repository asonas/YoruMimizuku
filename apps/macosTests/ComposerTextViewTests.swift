import AppKit
import XCTest

final class ComposerTextViewTests: XCTestCase {
    @MainActor
    func testBindingSynchronizationPreservesMarkedText() {
        let textView = AttachingTextView()
        textView.string = "下書き"
        textView.setMarkedText(
            "入力",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        let textDuringComposition = textView.string

        XCTAssertTrue(textView.hasMarkedText())

        textView.synchronizeTextFromBinding("古い下書き")

        XCTAssertEqual(textView.string, textDuringComposition)
        XCTAssertTrue(textView.hasMarkedText())
    }

    @MainActor
    func testBindingSynchronizationUpdatesTextOutsideComposition() {
        let textView = AttachingTextView()
        textView.string = "下書き"

        XCTAssertFalse(textView.hasMarkedText())

        textView.synchronizeTextFromBinding("更新された下書き")

        XCTAssertEqual(textView.string, "更新された下書き")
    }
}
