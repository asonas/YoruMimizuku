using System.Net;
using System.Text.RegularExpressions;

namespace YoruMimizuku.Core;

/// <summary>
/// Reads a link card from a page's Open Graph tags, for a bare URL in a post that has
/// no external embed. A pattern scan, not an HTML parser: only a few <c>&lt;meta&gt;</c>
/// and <c>&lt;title&gt;</c> tags matter. The patterns run without backtracking, so a
/// hostile page cannot make the scan slow.
/// </summary>
public static class Ogp
{
    private const RegexOptions Options = RegexOptions.IgnoreCase | RegexOptions.Singleline | RegexOptions.NonBacktracking;

    /// <summary>
    /// The card for the page at <paramref name="url"/>: <c>og:title</c> or else the
    /// <c>&lt;title&gt;</c>, <c>og:description</c> or else the meta description, and
    /// <c>og:image</c> resolved against the page. Null when the page has no title.
    /// </summary>
    public static LinkCard? Parse(string html, Uri url)
    {
        var title = Property(html, "og:title") ?? TitleTag(html);
        if (string.IsNullOrEmpty(title)) return null;
        var description = Property(html, "og:description") ?? Meta(html, "name", "description") ?? "";
        var thumb = Property(html, "og:image") is { } image && Uri.TryCreate(url, image, out var thumbUrl) ? thumbUrl : null;
        return new LinkCard(url, title, description, thumb);
    }

    /// <summary>A meta tag naming <paramref name="property"/> by <c>property</c> or <c>name</c>.</summary>
    private static string? Property(string html, string property) =>
        Meta(html, "property", property) ?? Meta(html, "name", property);

    /// <summary>The <c>content</c> of the meta tag whose <paramref name="attribute"/> is <paramref name="value"/>, in either attribute order.</summary>
    private static string? Meta(string html, string attribute, string value)
    {
        var key = $"""{attribute}\s*=\s*["']{Regex.Escape(value)}["']""";
        const string content = """content\s*=\s*["']([^"']*)["']""";
        var match = Regex.Match(html, $"<meta[^>]*{key}[^>]*{content}", Options);
        if (!match.Success) match = Regex.Match(html, $"<meta[^>]*{content}[^>]*{key}", Options);
        return match.Success ? WebUtility.HtmlDecode(match.Groups[1].Value) : null;
    }

    private static string? TitleTag(string html) =>
        Regex.Match(html, "<title[^>]*>([^<]*)</title>", Options) is { Success: true } match
            ? WebUtility.HtmlDecode(match.Groups[1].Value).Trim()
            : null;
}
