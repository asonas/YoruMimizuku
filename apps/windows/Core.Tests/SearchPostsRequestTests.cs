using System.Web;

namespace YoruMimizuku.Core.Tests;

public class SearchPostsRequestTests
{
    private static readonly Uri Pds = new("https://pds.example");

    [Fact]
    public void BuildsTheSearchPostsUriWithTheQueryAndLimit()
    {
        var uri = new SearchPostsRequest("#swift from:alice.bsky.social").ToUri(Pds);

        Assert.Equal("https://pds.example/xrpc/app.bsky.feed.searchPosts", uri.GetLeftPart(UriPartial.Path));
        var query = HttpUtility.ParseQueryString(uri.Query);
        Assert.Equal("#swift from:alice.bsky.social", query["q"]);
        Assert.Equal("25", query["limit"]);
        Assert.Null(query["cursor"]);
        Assert.Null(query["sort"]);
    }

    [Fact]
    public void IncludesCursorAndSortWhenSet()
    {
        var uri = new SearchPostsRequest("cats", Cursor: "page-2", Sort: "latest").ToUri(Pds);

        var query = HttpUtility.ParseQueryString(uri.Query);
        Assert.Equal("page-2", query["cursor"]);
        Assert.Equal("latest", query["sort"]);
    }

    // A query string decodes a literal '+' as a space. The Swift core leaves '+' unescaped
    // in the cursor, so the server reads a different cursor than the one it sent.
    [Fact]
    public void CursorWithPlusReachesTheServerUnchanged()
    {
        var uri = new SearchPostsRequest("cats", Cursor: "1718000000000+bafy/x=y&z").ToUri(Pds);

        Assert.Equal("1718000000000+bafy/x=y&z", HttpUtility.ParseQueryString(uri.Query)["cursor"]);
    }
}
