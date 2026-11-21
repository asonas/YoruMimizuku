namespace YoruMimizuku.Core.Tests;

public class FacetDetectorTests
{
    [Fact]
    public void DetectsBareLinkWithByteOffsets()
    {
        var facets = FacetDetector.Detect("see https://example.com now");

        Assert.Equal([new DetectedFacet(4, 23, new DetectedFeature.Link("https://example.com"))], facets);
    }

    [Fact]
    public void TrimsTrailingPunctuationFromLink()
    {
        var facets = FacetDetector.Detect("(https://example.com/path).");

        Assert.Equal(new DetectedFeature.Link("https://example.com/path"), Assert.Single(facets).Feature);
    }

    [Fact]
    public void DetectsHashtag()
    {
        var facets = FacetDetector.Detect("hello #swift world");

        Assert.Equal([new DetectedFacet(6, 12, new DetectedFeature.Tag("swift"))], facets);
    }

    [Fact]
    public void IgnoresNumericOnlyHashtag()
    {
        Assert.Empty(FacetDetector.Detect("code #123 here"));
    }

    [Fact]
    public void HashtagByteOffsetsWithMultibytePrefix()
    {
        // "あ" is 3 UTF-8 bytes; the tag starts after it plus a space.
        var facets = FacetDetector.Detect("あ #tag");

        Assert.Equal([new DetectedFacet(4, 8, new DetectedFeature.Tag("tag"))], facets);
    }

    [Fact]
    public void FullWidthHashtagByteOffsets()
    {
        // "＃" (U+FF03) is 3 UTF-8 bytes; "tag" is 3 bytes, so byteEnd is 6.
        var facets = FacetDetector.Detect("＃tag");

        Assert.Equal([new DetectedFacet(0, 6, new DetectedFeature.Tag("tag"))], facets);
    }

    [Fact]
    public void FullWidthHashtagByteOffsetsWithPrefix()
    {
        // "a " is 2 bytes, "＃" is 3 bytes, "b" is 1 byte: byteStart 2, byteEnd 6.
        var facets = FacetDetector.Detect("a ＃b");

        Assert.Equal([new DetectedFacet(2, 6, new DetectedFeature.Tag("b"))], facets);
    }

    [Fact]
    public void DetectsMentionCandidate()
    {
        var facets = FacetDetector.Detect("hi @alice.bsky.social !");

        Assert.Equal([new DetectedFacet(3, 21, new DetectedFeature.MentionCandidate("alice.bsky.social"))], facets);
    }

    [Fact]
    public void SortsMixedFacetsByByteStart()
    {
        var facets = FacetDetector.Detect("@bob.test #tag https://x.io");

        Assert.Equal(
            [
                new DetectedFeature.MentionCandidate("bob.test"),
                new DetectedFeature.Tag("tag"),
                new DetectedFeature.Link("https://x.io"),
            ],
            facets.Select(f => f.Feature));
    }

    /// Composed facets must render back to the same spans: Japanese text with a link and a tag.
    [Fact]
    public void JapaneseTextFacetsSliceBackToTheirSpans()
    {
        const string text = "日本語のリンク https://example.com/日本 と #タグ";

        var detected = FacetDetector.Detect(text);

        // 7 kana/kanji (21 bytes) and a space precede the link; "日本" adds 6 bytes to it.
        Assert.Equal([(22, 48), (53, 60)], detected.Select(f => (f.ByteStart, f.ByteEnd)));
        var facets = detected.Select(f => new Facet(f.ByteStart, f.ByteEnd, [f.Feature switch
        {
            DetectedFeature.Link link => new FacetFeature.Link(link.Uri),
            DetectedFeature.Tag tag => new FacetFeature.Tag(tag.Name),
            _ => throw new InvalidOperationException("No mention in this text."),
        }])).ToList();
        Assert.Equal(
            ["日本語のリンク ", "https://example.com/日本", " と ", "#タグ"],
            RichText.Segments(text, facets).Select(s => s.Text));
    }
}
