using System.Text;

namespace YoruMimizuku.Core.Tests;

public class RichTextSegmentTests
{
    [Fact]
    public void PlainTextWithoutFacetsIsOneTextSegment()
    {
        var segments = RichText.Segments("hello world", []);

        Assert.Equal([new RichTextSegment(RichTextSegmentKind.Text, "hello world", null)], segments);
    }

    [Fact]
    public void LinkFacetSplitsTextIntoSegments()
    {
        // "see https://example.com now": the link spans bytes 4..<23.
        var facets = new[] { new Facet(4, 23, [new FacetFeature.Link("https://example.com")]) };

        var segments = RichText.Segments("see https://example.com now", facets);

        Assert.Equal(
            [
                new RichTextSegment(RichTextSegmentKind.Text, "see ", null),
                new RichTextSegment(RichTextSegmentKind.Link, "https://example.com", new Uri("https://example.com")),
                new RichTextSegment(RichTextSegmentKind.Text, " now", null),
            ],
            segments);
    }

    /// A hostile post could carry a link facet whose URI is a non-web scheme
    /// (file://, custom app scheme). It must render as plain, non-tappable text
    /// so tapping it can never hand a file:// or app-scheme URL to the system.
    [Fact]
    public void NonWebLinkFacetFallsBackToPlainText()
    {
        const string uri = "file:///etc/passwd";
        var start = Encoding.UTF8.GetByteCount("open ");
        var facets = new[] { new Facet(start, start + Encoding.UTF8.GetByteCount(uri), [new FacetFeature.Link(uri)]) };

        var segments = RichText.Segments("open file:///etc/passwd now", facets);

        Assert.Equal([new RichTextSegment(RichTextSegmentKind.Text, "open file:///etc/passwd now", null)], segments);
    }

    [Fact]
    public void JavascriptLinkFacetFallsBackToPlainText()
    {
        const string uri = "javascript:alert(1)";
        var start = Encoding.UTF8.GetByteCount("tap ");
        var facets = new[] { new Facet(start, start + Encoding.UTF8.GetByteCount(uri), [new FacetFeature.Link(uri)]) };

        var segments = RichText.Segments("tap javascript:alert(1)", facets);

        Assert.Equal([RichTextSegmentKind.Text], segments.Select(s => s.Kind));
    }

    [Fact]
    public void TagFacetUsesHashtagUrl()
    {
        var facets = new[] { new Facet(5, 11, [new FacetFeature.Tag("swift")]) };

        var segments = RichText.Segments("love #swift", facets);

        Assert.Equal([RichTextSegmentKind.Text, RichTextSegmentKind.Tag], segments.Select(s => s.Kind));
        Assert.Equal("#swift", segments[1].Text);
        Assert.Equal(new Uri("https://bsky.app/hashtag/swift"), segments[1].Url);
    }

    [Fact]
    public void MentionFacetUsesProfileUrl()
    {
        var facets = new[] { new Facet(3, 19, [new FacetFeature.Mention("did:plc:bob")]) };

        var segments = RichText.Segments("hi @bob.bsky.social", facets);

        Assert.Equal([RichTextSegmentKind.Text, RichTextSegmentKind.Mention], segments.Select(s => s.Kind));
        Assert.Equal("@bob.bsky.social", segments[1].Text);
        Assert.Equal(new Uri("https://bsky.app/profile/did:plc:bob"), segments[1].Url);
    }

    [Fact]
    public void ByteOffsetsRespectMultibyteText()
    {
        // The owl emoji is 4 UTF-8 bytes (and two UTF-16 units); the link must still slice correctly.
        var prefixBytes = Encoding.UTF8.GetByteCount("🦉 ");
        var linkBytes = Encoding.UTF8.GetByteCount("https://example.com");
        var facets = new[] { new Facet(prefixBytes, prefixBytes + linkBytes, [new FacetFeature.Link("https://example.com")]) };

        var segments = RichText.Segments("🦉 https://example.com", facets);

        Assert.Equal(["🦉 ", "https://example.com"], segments.Select(s => s.Text));
        Assert.Equal([RichTextSegmentKind.Text, RichTextSegmentKind.Link], segments.Select(s => s.Kind));
    }

    [Fact]
    public void OutOfRangeFacetIsIgnored()
    {
        var facets = new[] { new Facet(0, 999, [new FacetFeature.Link("https://x")]) };

        var segments = RichText.Segments("short", facets);

        Assert.Equal([new RichTextSegment(RichTextSegmentKind.Text, "short", null)], segments);
    }

    [Fact]
    public void FacetWithoutSupportedFeatureFallsBackToText()
    {
        var facets = new[] { new Facet(0, 3, []) };

        var segments = RichText.Segments("abc", facets);

        Assert.Equal([new RichTextSegment(RichTextSegmentKind.Text, "abc", null)], segments);
    }

    [Fact]
    public void HashtagFromUrlExtractsTag()
    {
        Assert.Equal("swift", RichText.Hashtag(new Uri("https://bsky.app/hashtag/swift")));
    }

    /// The tag-building side percent-encodes; the reverse must decode it.
    [Fact]
    public void HashtagFromUrlDecodesMultibyteTag()
    {
        Assert.Equal("猫", RichText.Hashtag(new Uri("https://bsky.app/hashtag/%E7%8C%AB")));
    }

    [Fact]
    public void HashtagFromNonHashtagUrlIsNil()
    {
        Assert.Null(RichText.Hashtag(new Uri("https://bsky.app/profile/did:plc:bob")));
        Assert.Null(RichText.Hashtag(new Uri("https://example.com/page")));
    }

    [Fact]
    public void MentionDidExtractsDidFromProfileUrl()
    {
        Assert.Equal("did:plc:abc123", RichText.MentionDid(new Uri("https://bsky.app/profile/did:plc:abc123")));
    }

    [Fact]
    public void MentionDidExtractsHandleFromProfileUrl()
    {
        Assert.Equal("alice.bsky.social", RichText.MentionDid(new Uri("https://bsky.app/profile/alice.bsky.social")));
    }

    [Fact]
    public void MentionDidIsNilForPostPermalink()
    {
        Assert.Null(RichText.MentionDid(new Uri("https://bsky.app/profile/did:plc:abc123/post/3kabc")));
    }

    [Fact]
    public void MentionDidIsNilForHashtagUrl()
    {
        Assert.Null(RichText.MentionDid(new Uri("https://bsky.app/hashtag/swift")));
    }

    [Fact]
    public void MentionDidIsNilForForeignHost()
    {
        Assert.Null(RichText.MentionDid(new Uri("https://example.com/profile/did:plc:abc123")));
    }
}
