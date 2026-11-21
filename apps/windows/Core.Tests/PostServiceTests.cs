using System.Net;
using System.Text.Json;

namespace YoruMimizuku.Core.Tests;

public class PostServiceTests
{
    private const string PostsBody = """
        {
          "posts": [
            {
              "uri": "at://did:plc:me/app.bsky.feed.post/mine",
              "cid": "cidpost",
              "author": { "did": "did:plc:me", "handle": "me.bsky.social", "displayName": "Me" },
              "record": { "$type": "app.bsky.feed.post", "text": "hello world", "createdAt": "2026-06-04T12:00:00.000Z" },
              "replyCount": 0, "repostCount": 1, "likeCount": 2,
              "indexedAt": "2026-06-04T12:00:00.000Z"
            }
          ]
        }
        """;

    private const string Created = """{"uri":"at://did:plc:me/app.bsky.feed.post/new","cid":"bafynew"}""";

    private static readonly StrongRef Alice = new("at://did:plc:alice/app.bsky.feed.post/aaa", "bafyaaa");

    private sealed class FixedClock(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private static PostService Service(StubHttp http) =>
        new(http.Xrpc(), new FixedClock(new DateTimeOffset(2026, 6, 5, 0, 0, 0, 123, TimeSpan.Zero)));

    /// Answers each XRPC method from <paramref name="routes"/> by NSID, and 404 otherwise.
    private static StubHttp Routes(params (string Nsid, Func<HttpResponseMessage> Respond)[] routes) =>
        new(request => routes.FirstOrDefault(r => request.Path == "/xrpc/" + r.Nsid).Respond?.Invoke()
            ?? StubHttp.Json("""{"error":"MethodNotImplemented"}""", HttpStatusCode.NotFound));

    private static (string, Func<HttpResponseMessage>) Ok(string nsid, string json) => (nsid, () => StubHttp.Json(json));

    private static (string, Func<HttpResponseMessage>) Fail(string nsid, HttpStatusCode status) =>
        (nsid, () => StubHttp.Json("""{"error":"InvalidRequest"}""", status));

    private static JsonElement CreatedRecord(StubHttp http) =>
        http.Single("com.atproto.repo.createRecord").Json.GetProperty("record");

    private static string? Text(JsonElement json, string name) =>
        json.TryGetProperty(name, out var value) ? value.GetString() : null;

    [Fact]
    public async Task GetPostsSendsEveryUriAndDecodes()
    {
        var http = new StubHttp(PostsBody);
        string[] uris = ["at://did:plc:me/app.bsky.feed.post/mine", "at://did:plc:you/app.bsky.feed.post/yours"];

        var response = await new PostService(http.Xrpc()).GetPostsAsync(uris, CancellationToken.None);

        Assert.Equal("hello world", Assert.Single(response.Posts).Record.Text);
        Assert.Equal(HttpMethod.Get, http.Last.Method);
        Assert.Equal("/xrpc/app.bsky.feed.getPosts", http.Last.Path);
        Assert.Equal(uris, http.Last.Query.GetValues("uris")!);
    }

    [Fact]
    public async Task GetPostsWithNoUrisSendsNothing()
    {
        var http = new StubHttp(PostsBody);

        var response = await new PostService(http.Xrpc()).GetPostsAsync([], CancellationToken.None);

        Assert.Empty(response.Posts);
        Assert.Empty(http.Requests);
    }

    [Fact]
    public async Task CreatePostSendsThePostRecordToTheAccountsRepo()
    {
        var http = Routes(Ok("com.atproto.repo.createRecord", Created));

        var created = await Service(http).CreatePostAsync(new PostDraft("plain text"));

        Assert.Equal(new StrongRef("at://did:plc:me/app.bsky.feed.post/new", "bafynew"), created);
        var body = http.Single("com.atproto.repo.createRecord");
        Assert.Equal(HttpMethod.Post, body.Method);
        Assert.Equal("application/json", body.ContentType);
        Assert.Equal("did:plc:me", Text(body.Json, "repo"));
        Assert.Equal("app.bsky.feed.post", Text(body.Json, "collection"));
        var record = CreatedRecord(http);
        Assert.Equal("app.bsky.feed.post", Text(record, "$type"));
        Assert.Equal("plain text", Text(record, "text"));
        Assert.Equal("2026-06-05T00:00:00.123Z", Text(record, "createdAt"));
        Assert.False(record.TryGetProperty("facets", out _));
        Assert.False(record.TryGetProperty("embed", out _));
        Assert.False(record.TryGetProperty("reply", out _));
    }

    [Fact]
    public async Task CreatePostDropsTrailingBlankLinesButKeepsInteriorOnes()
    {
        var http = Routes(Ok("com.atproto.repo.createRecord", Created));

        await Service(http).CreatePostAsync(new PostDraft("one\n\ntwo\n\n  \n"));

        Assert.Equal("one\n\ntwo", Text(CreatedRecord(http), "text"));
    }

    [Fact]
    public async Task CreatePostResolvesTheMentionAndSendsFacetsAtUtf8Offsets()
    {
        var http = Routes(
            Ok("app.bsky.actor.getProfile", """{"did":"did:plc:alice","handle":"alice.bsky.social"}"""),
            Ok("com.atproto.repo.createRecord", Created));

        await Service(http).CreatePostAsync(new PostDraft("こんにちは @alice.bsky.social #swift https://x.io"));

        Assert.Equal("alice.bsky.social", http.Single("app.bsky.actor.getProfile").Query["actor"]);
        var facets = CreatedRecord(http).GetProperty("facets").EnumerateArray().ToList();
        // "こんにちは " is 16 bytes in UTF-8 (five 3-byte characters and a space).
        Assert.Equal(
            [(16, 34), (35, 41), (42, 54)],
            facets.Select(f => (f.GetProperty("index").GetProperty("byteStart").GetInt32(),
                f.GetProperty("index").GetProperty("byteEnd").GetInt32())));
        var features = facets.Select(f => Assert.Single(f.GetProperty("features").EnumerateArray())).ToList();
        Assert.Equal(
            ["app.bsky.richtext.facet#mention", "app.bsky.richtext.facet#tag", "app.bsky.richtext.facet#link"],
            features.Select(f => Text(f, "$type")));
        Assert.Equal("did:plc:alice", Text(features[0], "did"));
        Assert.Equal("swift", Text(features[1], "tag"));
        Assert.Equal("https://x.io", Text(features[2], "uri"));
    }

    [Fact]
    public async Task CreatePostLeavesAMentionPlainWhenTheHandleDoesNotResolve()
    {
        var http = Routes(
            Fail("app.bsky.actor.getProfile", HttpStatusCode.BadRequest),
            Ok("com.atproto.repo.createRecord", Created));

        var created = await Service(http).CreatePostAsync(new PostDraft("yo @ghost.invalid hello"));

        Assert.Equal("bafynew", created.Cid);
        Assert.False(CreatedRecord(http).TryGetProperty("facets", out _));
    }

    [Fact]
    public async Task CreatePostUploadsEachImageAndEmbedsItsBlobWithAltText()
    {
        const string blob = """{"$type":"blob","ref":{"$link":"bafycid"},"mimeType":"image/jpeg","size":3}""";
        var http = Routes(
            Ok("com.atproto.repo.uploadBlob", $$"""{"blob":{{blob}}}"""),
            Ok("com.atproto.repo.createRecord", Created));

        await Service(http).CreatePostAsync(
            new PostDraft("photo", [new DraftImage([0x1, 0x2, 0x3], "image/jpeg", "a cat")]));

        var upload = http.Single("com.atproto.repo.uploadBlob");
        Assert.Equal(HttpMethod.Post, upload.Method);
        Assert.Equal("image/jpeg", upload.ContentType);
        Assert.Equal([0x1, 0x2, 0x3], upload.Body);
        var embed = CreatedRecord(http).GetProperty("embed");
        Assert.Equal("app.bsky.embed.images", Text(embed, "$type"));
        var image = Assert.Single(embed.GetProperty("images").EnumerateArray());
        Assert.Equal("a cat", Text(image, "alt"));
        Assert.Equal(JsonSerializer.Serialize(JsonDocument.Parse(blob)), JsonSerializer.Serialize(image.GetProperty("image")));
    }

    [Fact]
    public async Task CreatePostWithAQuoteEmbedsTheQuotedRecord()
    {
        var http = Routes(Ok("com.atproto.repo.createRecord", Created));

        await Service(http).CreatePostAsync(new PostDraft("見て", Quote: Alice));

        var embed = CreatedRecord(http).GetProperty("embed");
        Assert.Equal("app.bsky.embed.record", Text(embed, "$type"));
        Assert.Equal(Alice.Uri, Text(embed.GetProperty("record"), "uri"));
        Assert.Equal(Alice.Cid, Text(embed.GetProperty("record"), "cid"));
    }

    [Fact]
    public async Task CreatePostWithAQuoteAndImagesNestsBothInRecordWithMedia()
    {
        var http = Routes(
            Ok("com.atproto.repo.uploadBlob", """{"blob":{"$type":"blob","ref":{"$link":"bafycid"},"mimeType":"image/png","size":1}}"""),
            Ok("com.atproto.repo.createRecord", Created));

        await Service(http).CreatePostAsync(new PostDraft("見て", [new DraftImage([0x1], "image/png", "")], Quote: Alice));

        var embed = CreatedRecord(http).GetProperty("embed");
        Assert.Equal("app.bsky.embed.recordWithMedia", Text(embed, "$type"));
        Assert.Equal("app.bsky.embed.record", Text(embed.GetProperty("record"), "$type"));
        Assert.Equal(Alice.Uri, Text(embed.GetProperty("record").GetProperty("record"), "uri"));
        Assert.Equal("app.bsky.embed.images", Text(embed.GetProperty("media"), "$type"));
        Assert.Single(embed.GetProperty("media").GetProperty("images").EnumerateArray());
    }

    [Fact]
    public async Task AReplyKeepsTheConversationRootOfAParentThatIsItselfAReply()
    {
        var http = Routes(
            Ok("com.atproto.repo.getRecord", """
                {"uri":"at://did:plc:bob/app.bsky.feed.post/parent","cid":"bafyparent",
                 "value":{"reply":{"root":{"uri":"at://did:plc:bob/app.bsky.feed.post/root","cid":"bafyroot"}}}}
                """),
            Ok("com.atproto.repo.createRecord", Created));

        await Service(http).CreatePostAsync(
            new PostDraft("thanks", ReplyParentUri: "at://did:plc:bob/app.bsky.feed.post/parent"));

        var getRecord = http.Single("com.atproto.repo.getRecord").Query;
        Assert.Equal(("did:plc:bob", "app.bsky.feed.post", "parent"), (getRecord["repo"], getRecord["collection"], getRecord["rkey"]));
        var reply = CreatedRecord(http).GetProperty("reply");
        Assert.Equal("at://did:plc:bob/app.bsky.feed.post/root", Text(reply.GetProperty("root"), "uri"));
        Assert.Equal("bafyroot", Text(reply.GetProperty("root"), "cid"));
        Assert.Equal("at://did:plc:bob/app.bsky.feed.post/parent", Text(reply.GetProperty("parent"), "uri"));
        Assert.Equal("bafyparent", Text(reply.GetProperty("parent"), "cid"));
    }

    [Fact]
    public async Task AReplyToATopLevelPostUsesTheParentAsRootAndKeepsItsFacets()
    {
        var http = Routes(
            Ok("app.bsky.actor.getProfile", """{"did":"did:plc:alice","handle":"alice.bsky.social"}"""),
            Ok("com.atproto.repo.getRecord", """
                {"uri":"at://did:plc:bob/app.bsky.feed.post/parent","cid":"bafyparent","value":{"text":"top"}}
                """),
            Ok("com.atproto.repo.createRecord", Created));

        await Service(http).CreatePostAsync(
            new PostDraft("@alice.bsky.social #swift https://x.io", ReplyParentUri: "at://did:plc:bob/app.bsky.feed.post/parent"));

        var record = CreatedRecord(http);
        var reply = record.GetProperty("reply");
        Assert.Equal("at://did:plc:bob/app.bsky.feed.post/parent", Text(reply.GetProperty("root"), "uri"));
        Assert.Equal("at://did:plc:bob/app.bsky.feed.post/parent", Text(reply.GetProperty("parent"), "uri"));
        Assert.Equal(3, record.GetProperty("facets").GetArrayLength());
    }

    [Fact]
    public async Task LikeCreatesALikeRecordOfThePostAndReturnsItsUri()
    {
        var http = Routes(Ok("com.atproto.repo.createRecord", """{"uri":"at://did:plc:me/app.bsky.feed.like/like1","cid":"bafylike"}"""));

        var like = await Service(http).LikeAsync(Alice);

        Assert.Equal("at://did:plc:me/app.bsky.feed.like/like1", like);
        var body = http.Single("com.atproto.repo.createRecord").Json;
        Assert.Equal("did:plc:me", Text(body, "repo"));
        Assert.Equal("app.bsky.feed.like", Text(body, "collection"));
        var record = body.GetProperty("record");
        Assert.Equal("app.bsky.feed.like", Text(record, "$type"));
        Assert.Equal("2026-06-05T00:00:00.123Z", Text(record, "createdAt"));
        Assert.Equal(Alice.Uri, Text(record.GetProperty("subject"), "uri"));
        Assert.Equal(Alice.Cid, Text(record.GetProperty("subject"), "cid"));
    }

    [Fact]
    public async Task RepostCreatesARepostRecordOfThePostAndReturnsItsUri()
    {
        var http = Routes(Ok("com.atproto.repo.createRecord", """{"uri":"at://did:plc:me/app.bsky.feed.repost/rp1","cid":"bafyrp"}"""));

        var repost = await Service(http).RepostAsync(Alice);

        Assert.Equal("at://did:plc:me/app.bsky.feed.repost/rp1", repost);
        var body = http.Single("com.atproto.repo.createRecord").Json;
        Assert.Equal("app.bsky.feed.repost", Text(body, "collection"));
        Assert.Equal("app.bsky.feed.repost", Text(body.GetProperty("record"), "$type"));
        Assert.Equal(Alice.Uri, Text(body.GetProperty("record").GetProperty("subject"), "uri"));
    }

    [Fact]
    public async Task UnlikeUnrepostAndDeleteRemoveTheRecordFromTheAccountsRepo()
    {
        var http = Routes(Ok("com.atproto.repo.deleteRecord", "{}"));
        var service = Service(http);

        await service.UnlikeAsync("at://did:plc:me/app.bsky.feed.like/like1");
        await service.UnrepostAsync("at://did:plc:me/app.bsky.feed.repost/rp1");
        await service.DeletePostAsync("at://did:plc:me/app.bsky.feed.post/p1");

        Assert.All(http.Requests, r => Assert.Equal(HttpMethod.Post, r.Method));
        Assert.Equal(
            [
                ("did:plc:me", "app.bsky.feed.like", "like1"),
                ("did:plc:me", "app.bsky.feed.repost", "rp1"),
                ("did:plc:me", "app.bsky.feed.post", "p1"),
            ],
            http.Requests.Select(r => (Text(r.Json, "repo"), Text(r.Json, "collection"), Text(r.Json, "rkey"))));
    }
}
