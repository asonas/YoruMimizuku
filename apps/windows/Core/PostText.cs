namespace YoruMimizuku.Core;

/// <summary>Text normalization applied when a post is submitted.</summary>
public static class PostText
{
    /// <summary>
    /// Removes whitespace and line breaks from the end only, so trailing blank lines are
    /// never published; interior line breaks stay. All-whitespace input becomes empty.
    /// </summary>
    public static string TrimTrailingWhitespace(string text) => text.TrimEnd();
}
