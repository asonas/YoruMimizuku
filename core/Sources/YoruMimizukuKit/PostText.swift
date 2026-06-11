import Foundation

/// Text normalization applied at the post-submission boundary, shared across
/// platforms (the macOS composer view model and the Windows bridge both call
/// it) so trailing blank lines are never published verbatim.
public enum PostText {
    /// Remove whitespace and newlines only from the end of the text, leaving
    /// interior line breaks untouched. All-whitespace input becomes empty.
    public static func trimmingTrailingWhitespace(of text: String) -> String {
        guard let lastNonWhitespace = text.rangeOfCharacter(
            from: CharacterSet.whitespacesAndNewlines.inverted, options: .backwards
        ) else { return "" }
        return String(text[..<lastNonWhitespace.upperBound])
    }
}
