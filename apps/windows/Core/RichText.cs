using System.Text;

namespace YoruMimizuku.Core;

public enum RichTextSegmentKind
{
    Text,
    Link,
    Tag,
    Mention,
}

/// <summary>One display span of a post body. Links, hashtags and mentions carry the URL a tap opens.</summary>
public sealed record RichTextSegment(RichTextSegmentKind Kind, string Text, Uri? Url);

/// <summary>Turns post text plus its facets into display spans, and reads app URLs back.</summary>
public static class RichText
{
    private const string Host = "bsky.app";

    /// <summary>
    /// Splits <paramref name="text"/> at its facets. Facet ranges are UTF-8 byte offsets,
    /// so slicing happens on the UTF-8 bytes. A facet that is out of range, overlaps an
    /// earlier one, or has no supported feature stays plain text, as does a link whose
    /// scheme is not http or https.
    /// </summary>
    public static IReadOnlyList<RichTextSegment> Segments(string text, IReadOnlyList<Facet> facets)
    {
        var bytes = Encoding.UTF8.GetBytes(text);
        var spans = facets
            .Where(f => f.ByteStart >= 0 && f.ByteEnd <= bytes.Length && f.ByteStart < f.ByteEnd)
            .Select(f => (Facet: f, Target: f.Features.Select(Target).FirstOrDefault(t => t is not null)))
            .Where(span => span.Target is not null)
            .OrderBy(span => span.Facet.ByteStart);

        var segments = new List<RichTextSegment>();
        var cursor = 0;
        foreach (var (facet, target) in spans)
        {
            if (facet.ByteStart < cursor) continue;
            AddText(cursor, facet.ByteStart);
            segments.Add(new RichTextSegment(target!.Value.Kind, Slice(facet.ByteStart, facet.ByteEnd), target.Value.Url));
            cursor = facet.ByteEnd;
        }
        AddText(cursor, bytes.Length);
        return segments;

        string Slice(int start, int end) => Encoding.UTF8.GetString(bytes, start, end - start);

        void AddText(int start, int end)
        {
            if (start < end) segments.Add(new RichTextSegment(RichTextSegmentKind.Text, Slice(start, end), null));
        }
    }

    /// <summary>The tag of a <c>https://bsky.app/hashtag/&lt;tag&gt;</c> URL, percent-decoded; null for any other URL.</summary>
    public static string? Hashtag(Uri url) => SecondSegment(url, "hashtag");

    /// <summary>The DID or handle of a bare <c>https://bsky.app/profile/&lt;id&gt;</c> URL; null for any other URL.</summary>
    public static string? MentionDid(Uri url) => SecondSegment(url, "profile");

    private static string? SecondSegment(Uri url, string first)
    {
        if (url.Host != Host) return null;
        var parts = url.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length == 2 && parts[0] == first ? Uri.UnescapeDataString(parts[1]) : null;
    }

    private static (RichTextSegmentKind Kind, Uri? Url)? Target(FacetFeature feature) => feature switch
    {
        FacetFeature.Link link =>
            Uri.TryCreate(link.Uri, UriKind.Absolute, out var url) && (url.Scheme == Uri.UriSchemeHttp || url.Scheme == Uri.UriSchemeHttps)
                ? (RichTextSegmentKind.Link, url)
                : null,
        FacetFeature.Tag tag => (RichTextSegmentKind.Tag, AppUrl($"hashtag/{Uri.EscapeDataString(tag.Name)}")),
        FacetFeature.Mention mention => (RichTextSegmentKind.Mention, AppUrl($"profile/{mention.Did}")),
        _ => null,
    };

    private static Uri? AppUrl(string path) =>
        Uri.TryCreate($"https://{Host}/{path}", UriKind.Absolute, out var url) ? url : null;
}
