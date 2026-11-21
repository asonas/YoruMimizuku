using System.Net;

namespace YoruMimizuku.Core.Tests;

public class LinkPreviewLoaderTests
{
    private static readonly Uri Article = new("https://example.com/article");

    private static StubHttp Page(string html, HttpStatusCode status = HttpStatusCode.OK) =>
        new(_ => new HttpResponseMessage(status) { Content = new StringContent(html, System.Text.Encoding.UTF8, "text/html") });

    [Fact]
    public async Task LoadsThePageAndReadsItsCard()
    {
        var http = Page("""<meta property="og:title" content="Card"><meta property="og:description" content="desc">""");

        var card = await new LinkPreviewLoader(new HttpClient(http)).PreviewAsync(Article);

        Assert.Equal(new LinkCard(Article, "Card", "desc", null), card);
        Assert.Equal(HttpMethod.Get, http.Last.Method);
        Assert.Equal(Article, http.Last.Uri);
    }

    [Fact]
    public async Task FetchesEachUrlOnce()
    {
        var http = Page("""<meta property="og:title" content="Card">""");
        var loader = new LinkPreviewLoader(new HttpClient(http));

        await loader.PreviewAsync(Article);
        await loader.PreviewAsync(Article);

        Assert.Single(http.Requests);
    }

    [Fact]
    public async Task AFailedFetchYieldsNoCardAndIsNotRetried()
    {
        var http = Page("oops", HttpStatusCode.InternalServerError);
        var loader = new LinkPreviewLoader(new HttpClient(http));

        Assert.Null(await loader.PreviewAsync(Article));
        Assert.Null(await loader.PreviewAsync(Article));
        Assert.Single(http.Requests);
    }

    // Post text is written by anyone, so only web links are ever fetched.
    [Fact]
    public async Task OnlyWebLinksAreFetched()
    {
        var http = Page("""<meta property="og:title" content="Card">""");

        var card = await new LinkPreviewLoader(new HttpClient(http)).PreviewAsync(new Uri("file:///C:/Windows/win.ini"));

        Assert.Null(card);
        Assert.Empty(http.Requests);
    }
}
