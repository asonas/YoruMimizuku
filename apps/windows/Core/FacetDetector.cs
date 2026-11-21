using System.Buffers;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace YoruMimizuku.Core;

/// <summary>A facet found in composed text. Offsets are UTF-8 bytes, as the lexicon requires.</summary>
public sealed record DetectedFacet(int ByteStart, int ByteEnd, DetectedFeature Feature);

/// <summary>
/// What a detected range is. A mention is only a candidate: its handle still has to
/// resolve to a DID, and the facet is dropped when it does not.
/// </summary>
public abstract record DetectedFeature
{
    private DetectedFeature() { }

    public sealed record Link(string Uri) : DetectedFeature;

    public sealed record Tag(string Name) : DetectedFeature;

    public sealed record MentionCandidate(string Handle) : DetectedFeature;
}

/// <summary>Finds links, hashtags and mentions in text being posted.</summary>
public static partial class FacetDetector
{
    /// <summary>All facets in <paramref name="text"/>, sorted by byte start.</summary>
    public static IReadOnlyList<DetectedFacet> Detect(string text) =>
        DetectLinks(text).Concat(DetectTags(text)).Concat(DetectMentions(text)).OrderBy(f => f.ByteStart).ToList();

    [GeneratedRegex(@"https?://[^\s]+")]
    private static partial Regex LinkPattern();

    // At text start or after whitespace; '#' or full-width '＃'; at least one character
    // that is not a digit or punctuation, so a bare "#123" is not a tag.
    [GeneratedRegex(@"(?:^|\s)[#＃]([^\s#＃]*[^\d\s\p{P}#＃]+[^\s#＃]*)")]
    private static partial Regex TagPattern();

    // At text start or after whitespace, '(' or '['; a domain-shaped handle.
    [GeneratedRegex(@"(?:^|[\s(\[])@([a-zA-Z0-9._-]+\.[a-zA-Z]{2,})")]
    private static partial Regex MentionPattern();

    private const int MaxTagGraphemes = 64;

    // Closing punctuation of a sentence is not part of the link it follows.
    private const string LinkTrailing = ".,;:!?)\"']";

    private static IEnumerable<DetectedFacet> DetectLinks(string text)
    {
        foreach (Match match in LinkPattern().Matches(text))
        {
            var uri = TrimLinkEnd(match.Value);
            var start = ByteOffset(text, match.Index);
            yield return new DetectedFacet(start, start + Encoding.UTF8.GetByteCount(uri), new DetectedFeature.Link(uri));
        }
    }

    // Matches the Swift core: a closing paren is kept only while the link has more
    // '(' than ')', so a balanced "(…)" at the end is stripped too.
    private static string TrimLinkEnd(string uri)
    {
        while (LinkTrailing.Contains(uri[^1]))
        {
            if (uri[^1] == ')' && uri.Count(c => c == '(') > uri.Count(c => c == ')')) break;
            uri = uri[..^1];
        }
        return uri;
    }

    private static IEnumerable<DetectedFacet> DetectTags(string text)
    {
        foreach (Match match in TagPattern().Matches(text))
        {
            var body = match.Groups[1];
            var tag = TrimPunctuationEnd(body.Value);
            if (new StringInfo(tag).LengthInTextElements > MaxTagGraphemes) continue;
            // The marker sits one UTF-16 unit before the body: '#' is 1 byte, '＃' is 3.
            yield return new DetectedFacet(
                ByteOffset(text, body.Index - 1),
                ByteOffset(text, body.Index) + Encoding.UTF8.GetByteCount(tag),
                new DetectedFeature.Tag(tag));
        }
    }

    private static string TrimPunctuationEnd(string value)
    {
        while (Rune.DecodeLastFromUtf16(value, out var rune, out var length) == OperationStatus.Done
               && Rune.IsPunctuation(rune))
        {
            value = value[..^length];
        }
        return value;
    }

    private static IEnumerable<DetectedFacet> DetectMentions(string text)
    {
        foreach (Match match in MentionPattern().Matches(text))
        {
            var handle = match.Groups[1];
            yield return new DetectedFacet(
                ByteOffset(text, handle.Index - 1),
                ByteOffset(text, handle.Index) + Encoding.UTF8.GetByteCount(handle.Value),
                new DetectedFeature.MentionCandidate(handle.Value));
        }
    }

    private static int ByteOffset(string text, int utf16Index) => Encoding.UTF8.GetByteCount(text.AsSpan(0, utf16Index));
}
