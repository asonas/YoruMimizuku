namespace YoruMimizuku.Core.Tests;

public class OgpTests
{
    private static readonly Uri PageUrl = new("https://example.com/blog/post");

    [Fact]
    public void ParsesOpenGraphTags()
    {
        const string html = """
            <html><head>
            <meta property="og:title" content="An Article">
            <meta property="og:description" content="Worth reading.">
            <meta property="og:image" content="https://cdn.example.com/hero.jpg">
            <title>fallback title</title>
            </head><body></body></html>
            """;

        var card = Ogp.Parse(html, PageUrl);

        Assert.Equal(new LinkCard(PageUrl, "An Article", "Worth reading.", new Uri("https://cdn.example.com/hero.jpg")), card);
    }

    [Fact]
    public void ParsesReversedAttributeOrderAndSingleQuotes()
    {
        const string html = """
            <meta content='Reversed' property='og:title'/>
            <meta content='https://cdn.example.com/i.png' property='og:image' />
            """;

        var card = Ogp.Parse(html, PageUrl);

        Assert.Equal("Reversed", card?.Title);
        Assert.Equal(new Uri("https://cdn.example.com/i.png"), card?.ThumbUrl);
    }

    [Fact]
    public void FallsBackToTitleTagAndMetaDescription()
    {
        const string html = """
            <html><head>
            <title>Plain Title</title>
            <meta name="description" content="Plain description.">
            </head></html>
            """;

        var card = Ogp.Parse(html, PageUrl);

        Assert.Equal("Plain Title", card?.Title);
        Assert.Equal("Plain description.", card?.Description);
        Assert.Null(card?.ThumbUrl);
    }

    [Fact]
    public void DecodesHtmlEntities()
    {
        const string html = """<meta property="og:title" content="Q&amp;A &#x27;quoted&#x27; &lt;tag&gt; &#12354;">""";

        Assert.Equal("Q&A 'quoted' <tag> あ", Ogp.Parse(html, PageUrl)?.Title);
    }

    [Fact]
    public void ResolvesARelativeImageUrlAgainstThePage()
    {
        const string html = """
            <meta property="og:title" content="t">
            <meta property="og:image" content="/images/hero.jpg">
            """;

        Assert.Equal(new Uri("https://example.com/images/hero.jpg"), Ogp.Parse(html, PageUrl)?.ThumbUrl);
    }

    [Fact]
    public void ReturnsNullWithoutAnyTitle()
    {
        Assert.Null(Ogp.Parse("<html><body>no metadata here</body></html>", PageUrl));
    }

    [Fact]
    public void TrimsWhitespaceAroundTheTitleTag()
    {
        Assert.Equal("Spaced Out", Ogp.Parse("<title>\n  Spaced Out \n</title>", PageUrl)?.Title);
    }
}
