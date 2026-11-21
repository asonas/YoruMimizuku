using System.Net;
using System.Text.Json;
using YoruMimizuku.Core.Tests;

namespace YoruMimizuku.App.Interop.Tests;

/// <summary>Writes from the objects the view models build, and failures in the bridge's error shape.</summary>
public class WriteAndFailureTests
{
    private const string Blob = """{"blob":{"$type":"blob","ref":{"$link":"bafycid"},"mimeType":"image/png","size":3}}""";
    private const string TopLevelParent = """{"uri":"at://did:plc:bob/app.bsky.feed.post/parent","cid":"bafyparent","value":{"text":"top"}}""";
    private const string Created = """{"uri":"at://did:plc:me/app.bsky.feed.post/new","cid":"bafynew"}""";

    private static StubHttp Routes(params (string Nsid, string Body)[] routes) =>
        new(request => routes.FirstOrDefault(r => request.Path == "/xrpc/" + r.Nsid).Body is { } body
            ? StubHttp.Json(body)
            : StubHttp.Json("""{"error":"MethodNotImplemented"}""", HttpStatusCode.NotFound));

    private static string? Text(JsonElement json, string name) => json.GetProperty(name).GetString();

    [Fact]
    public async Task PostCreateTakesTheDraftTheComposerBuilds()
    {
        var http = Routes(
            ("com.atproto.repo.uploadBlob", Blob),
            ("com.atproto.repo.getRecord", TopLevelParent),
            ("com.atproto.repo.createRecord", Created));
        // ComposerViewModel.SubmitAsync's draft, with one image whose data is not base64.
        var draft = new
        {
            text = "見て\n\n",
            images = new List<object>
            {
                new { dataBase64 = Convert.ToBase64String(new byte[] { 1, 2, 3 }), mimeType = "image/png", alt = "a cat" },
                new { dataBase64 = "not base64!", mimeType = "image/jpeg", alt = "" },
            },
            replyParentURI = "at://did:plc:bob/app.bsky.feed.post/parent",
            quote = new { uri = "at://did:plc:alice/app.bsky.feed.post/aaa", cid = "bafyaaa" },
        };

        var result = await new CoreAccountClient(http.Xrpc()).PostCreateAsync(draft);

        var upload = http.Single("com.atproto.repo.uploadBlob");
        Assert.Equal("image/png", upload.ContentType);
        Assert.Equal([1, 2, 3], upload.Body);
        var record = http.Single("com.atproto.repo.createRecord").Json.GetProperty("record");
        Assert.Equal("見て", Text(record, "text"));
        var embed = record.GetProperty("embed");
        Assert.Equal("app.bsky.embed.recordWithMedia", Text(embed, "$type"));
        Assert.Equal("a cat", Text(Assert.Single(embed.GetProperty("media").GetProperty("images").EnumerateArray()), "alt"));
        Assert.Equal("at://did:plc:alice/app.bsky.feed.post/aaa", Text(embed.GetProperty("record").GetProperty("record"), "uri"));
        Assert.Equal("at://did:plc:bob/app.bsky.feed.post/parent", Text(record.GetProperty("reply").GetProperty("root"), "uri"));
        Assert.Equal(new PostResultDto("at://did:plc:me/app.bsky.feed.post/new", "bafynew"), result);
    }

    [Fact]
    public async Task LikesRepostsAndDeletesActOnTheMatchingCollection()
    {
        var http = Routes(("com.atproto.repo.createRecord", Created), ("com.atproto.repo.deleteRecord", "{}"));
        var client = new CoreAccountClient(http.Xrpc());

        var like = await client.LikeAsync("at://did:plc:alice/app.bsky.feed.post/aaa", "bafyaaa");
        var repost = await client.RepostAsync("at://did:plc:alice/app.bsky.feed.post/aaa", "bafyaaa");
        await client.UnlikeAsync("at://did:plc:me/app.bsky.feed.like/l1");
        await client.UnrepostAsync("at://did:plc:me/app.bsky.feed.repost/r1");
        await client.DeletePostAsync("at://did:plc:me/app.bsky.feed.post/p1");

        Assert.Equal(new RecordRefDto("at://did:plc:me/app.bsky.feed.post/new"), like);
        Assert.Equal(new RecordRefDto("at://did:plc:me/app.bsky.feed.post/new"), repost);
        var writes = http.Requests.Select(r => (r.Path, Text(r.Json, "repo"), Text(r.Json, "collection"))).ToList();
        Assert.Equal(
            [
                ("/xrpc/com.atproto.repo.createRecord", "did:plc:me", "app.bsky.feed.like"),
                ("/xrpc/com.atproto.repo.createRecord", "did:plc:me", "app.bsky.feed.repost"),
                ("/xrpc/com.atproto.repo.deleteRecord", "did:plc:me", "app.bsky.feed.like"),
                ("/xrpc/com.atproto.repo.deleteRecord", "did:plc:me", "app.bsky.feed.repost"),
                ("/xrpc/com.atproto.repo.deleteRecord", "did:plc:me", "app.bsky.feed.post"),
            ],
            writes);
        Assert.Equal(["l1", "r1", "p1"], http.Requests.Skip(2).Select(r => Text(r.Json, "rkey")));
    }

    [Fact]
    public async Task AFailedLoadCarriesTheLoadFailureClassification()
    {
        var http = new StubHttp(_ => StubHttp.Json("""{"error":"InternalServerError"}""", HttpStatusCode.InternalServerError));

        var error = await Assert.ThrowsAsync<CoreException>(() => new CoreAccountClient(http.Xrpc()).TimelineLoadAsync());

        Assert.Equal("server", error.Kind);
        Assert.Equal("サーバーエラー", error.Title);
        Assert.Equal("サーバー側で問題が発生しました。時間をおいて再試行してください。", error.FriendlyMessage);
        Assert.Contains("HTTP 500", error.Message);
        Assert.False(error.SessionExpired);
    }

    private sealed class SessionGone() : Exception("invalid_grant");

    [Fact]
    public async Task TheAuthLayersExpiredSessionIsFlagged()
    {
        var http = new StubHttp(_ => throw new SessionGone());
        var client = new CoreAccountClient(http.Xrpc(), error => error is SessionGone);

        var error = await Assert.ThrowsAsync<CoreException>(() => client.LikeAsync("at://did:plc:a/app.bsky.feed.post/a", "c"));

        Assert.True(error.SessionExpired);
        Assert.Equal("unknown", error.Kind);
    }
}
