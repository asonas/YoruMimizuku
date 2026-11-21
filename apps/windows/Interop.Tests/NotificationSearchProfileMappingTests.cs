using System.Text.Json.Nodes;
using YoruMimizuku.Core.Tests;

namespace YoruMimizuku.App.Interop.Tests;

/// <summary>
/// Notification rows, saved-filter searches and profiles as the views receive them,
/// from the core tests' fixtures (NotificationGroupTests, NotificationServiceTests,
/// SearchServiceTests, ProfileServiceTests).
/// </summary>
public class NotificationSearchProfileMappingTests
{
    private static CoreAccountClient Client(StubHttp http) => new(http.Xrpc());

    // NotificationGroupTests.LivePage: a like, a reply and a reason the app does not know.
    private const string LivePage = """
    {
      "cursor": "2026-06-10T08:55:37.066Z",
      "notifications": [
        {
          "uri": "at://did:plc:liker/app.bsky.feed.like/3mnwxyz",
          "cid": "bafylike",
          "author": {
            "did": "did:plc:liker", "handle": "liker.bsky.social", "displayName": "Liker",
            "avatar": "https://cdn.bsky.app/img/avatar/plain/did:plc:liker/bafkavatar",
            "associated": { "chat": { "allowIncoming": "following" } }, "labels": [], "createdAt": "2023-06-22T14:05:03.241Z"
          },
          "reason": "like",
          "reasonSubject": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m",
          "record": {
            "$type": "app.bsky.feed.like", "createdAt": "2026-06-10T09:00:00.000Z",
            "subject": { "cid": "bafyparent", "uri": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m" }
          },
          "isRead": false,
          "indexedAt": "2026-06-10T09:00:01.000Z"
        },
        {
          "uri": "at://did:plc:replier/app.bsky.feed.post/3mnwdnozac22s",
          "cid": "bafyreply",
          "author": {
            "did": "did:plc:replier", "handle": "replier.s01.ninja", "displayName": "Replier / G4",
            "avatar": "https://cdn.bsky.app/img/avatar/plain/did:plc:replier/bafkavatar2", "labels": [], "createdAt": "2023-06-22T14:05:03.241Z"
          },
          "reason": "reply",
          "reasonSubject": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m",
          "record": {
            "$type": "app.bsky.feed.post", "createdAt": "2026-06-10T08:55:21.213Z", "langs": ["ja"],
            "reply": {
              "parent": { "cid": "bafyparent", "uri": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m" },
              "root": { "cid": "bafyparent", "uri": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m" }
            },
            "text": ":eyes:"
          },
          "isRead": false,
          "indexedAt": "2026-06-10T08:55:37.066Z"
        },
        {
          "uri": "at://did:plc:subbed/app.bsky.feed.post/3mnwsub",
          "cid": "bafysub",
          "author": { "did": "did:plc:subbed", "handle": "subbed.bsky.social" },
          "reason": "subscribed-post",
          "record": { "$type": "app.bsky.feed.post", "createdAt": "2026-06-10T08:00:00.000Z", "text": "subscribed activity" },
          "isRead": true,
          "indexedAt": "2026-06-10T08:00:01.000Z"
        }
      ]
    }
    """;

    // NotificationServiceTests.PostsBody, for the liked post above.
    private const string SubjectBody = """
    {
      "posts": [
        {
          "uri": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m",
          "cid": "cidpost",
          "author": { "did": "did:plc:me", "handle": "me.bsky.social" },
          "record": { "text": "hello world", "createdAt": "2026-06-04T10:00:00.000Z" },
          "embed": {
            "$type": "app.bsky.embed.images#view",
            "images": [ { "thumb": "https://cdn.example/t.jpg", "fullsize": "https://cdn.example/f.jpg", "alt": "" } ]
          },
          "indexedAt": "2026-06-04T10:00:00.000Z"
        }
      ]
    }
    """;

    /// Only like and repost subjects are fetched, but as in the bridge, any row about a
    /// fetched post shows it, so the reply to the liked post carries its text too.
    [Fact]
    public async Task NotificationRowsMapLikeTheBridge()
    {
        var http = new StubHttp(request => StubHttp.Json(
            request.Path == "/xrpc/app.bsky.feed.getPosts" ? SubjectBody : LivePage));

        var groups = await Client(http).NotificationsLoadAsync();

        BridgeJson.Equal("""
        [
          {
            "id": "like|at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m", "reason": "like",
            "actors": [ { "displayName": "Liker", "handle": "liker.bsky.social", "avatarUrl": "https://cdn.bsky.app/img/avatar/plain/did:plc:liker/bafkavatar" } ],
            "subjectUri": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m",
            "subjectText": "hello world", "subjectImageUrl": "https://cdn.example/t.jpg",
            "latestCreatedAt": "2026-06-10T09:00:01.000Z", "isRead": false
          },
          {
            "id": "single|at://did:plc:replier/app.bsky.feed.post/3mnwdnozac22s|bafyreply", "reason": "reply",
            "actors": [ { "displayName": "Replier / G4", "handle": "replier.s01.ninja", "avatarUrl": "https://cdn.bsky.app/img/avatar/plain/did:plc:replier/bafkavatar2" } ],
            "subjectUri": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m",
            "subjectText": "hello world", "subjectImageUrl": "https://cdn.example/t.jpg",
            "text": ":eyes:", "latestCreatedAt": "2026-06-10T08:55:37.066Z", "isRead": false
          },
          {
            "id": "single|at://did:plc:subbed/app.bsky.feed.post/3mnwsub|bafysub", "reason": "other",
            "actors": [ { "displayName": "subbed.bsky.social", "handle": "subbed.bsky.social" } ],
            "text": "subscribed activity", "latestCreatedAt": "2026-06-10T08:00:01.000Z", "isRead": true
          }
        ]
        """, groups);
    }

    // SearchServiceTests.SearchBody, and a newer post for the second subquery.
    private const string AliceResults = """
    {
      "cursor": "next",
      "posts": [
        {
          "uri": "at://did:plc:alice/app.bsky.feed.post/aaa", "cid": "bafyreialice",
          "author": { "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice" },
          "record": { "$type": "app.bsky.feed.post", "text": "hi #swift", "createdAt": "2026-06-04T12:00:00.000Z" },
          "indexedAt": "2026-06-04T12:00:01.000Z"
        }
      ]
    }
    """;

    private const string SwiftResults = """
    {
      "posts": [
        {
          "uri": "at://did:plc:bob/app.bsky.feed.post/bbb", "cid": "bafyreibob",
          "author": { "did": "did:plc:bob", "handle": "bob.bsky.social" },
          "record": { "$type": "app.bsky.feed.post", "text": "swift", "createdAt": "2026-06-04T13:00:00.000Z" },
          "indexedAt": "2026-06-04T13:00:01.000Z"
        },
        {
          "uri": "at://did:plc:alice/app.bsky.feed.post/aaa", "cid": "bafyreialice",
          "author": { "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice" },
          "record": { "$type": "app.bsky.feed.post", "text": "hi #swift", "createdAt": "2026-06-04T12:00:00.000Z" },
          "indexedAt": "2026-06-04T12:00:01.000Z"
        }
      ]
    }
    """;

    /// The object SavedFilterModel.ToBridgeJson builds: camelCase, lowercase raw values, no createdAt.
    private static JsonObject AppFilter() => JsonNode.Parse("""
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "name": "Two terms",
          "terms": [
            { "id": "33333333-3333-3333-3333-333333333333", "kind": "user", "value": "@alice.bsky.social" },
            { "id": "44444444-4444-4444-4444-444444444444", "kind": "hashtag", "value": "swift" }
          ],
          "combinator": "or"
        }
        """)!.AsObject();

    [Fact]
    public async Task OrFilterFromTheAppSearchesEachTermAndMergesNewestFirst()
    {
        var http = new StubHttp(request => StubHttp.Json(
            request.Query["q"] == "from:alice.bsky.social" ? AliceResults : SwiftResults));

        var page = await Client(http).SearchLoadAsync(AppFilter());

        var searches = http.Requests.Select(r => (r.Query["q"], r.Query["sort"])).OrderBy(s => s.Item1).ToList();
        Assert.Equal([("#swift", "latest"), ("from:alice.bsky.social", "latest")], searches);
        Assert.NotNull(page.Cursor);
        BridgeJson.Equal("""
        [
          {
            "id": "at://did:plc:bob/app.bsky.feed.post/bbb", "cid": "bafyreibob",
            "authorDisplayName": "bob.bsky.social", "authorHandle": "bob.bsky.social",
            "body": "swift", "segments": [ { "kind": "text", "text": "swift" } ],
            "createdAt": "2026-06-04T13:00:00.000Z", "images": [],
            "replyCount": 0, "repostCount": 0, "likeCount": 0, "isLiked": false, "isReposted": false
          },
          {
            "id": "at://did:plc:alice/app.bsky.feed.post/aaa", "cid": "bafyreialice",
            "authorDisplayName": "Alice", "authorHandle": "alice.bsky.social",
            "body": "hi #swift", "segments": [ { "kind": "text", "text": "hi #swift" } ],
            "createdAt": "2026-06-04T12:00:00.000Z", "images": [],
            "replyCount": 0, "repostCount": 0, "likeCount": 0, "isLiked": false, "isReposted": false
          }
        ]
        """, page.Posts);
    }

    // ProfileServiceTests.ProfileBody.
    private const string ProfileBody = """
    {
      "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice",
      "avatar": "https://cdn.example/alice.jpg", "description": "hello",
      "followersCount": 10, "followsCount": 20, "postsCount": 30
    }
    """;

    /// The bridge reads a basic profile, so the bio stays empty even when the server sends one.
    [Fact]
    public async Task ProfileAndAvatarMapLikeTheBridge()
    {
        var http = new StubHttp(ProfileBody);
        var client = Client(http);

        var profile = await client.ProfileAsync("alice.bsky.social");
        Assert.Equal("alice.bsky.social", http.Last.Query["actor"]);
        var avatar = await client.AvatarAsync();
        Assert.Equal("did:plc:me", http.Last.Query["actor"]);

        BridgeJson.Equal("""
            { "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice", "avatarUrl": "https://cdn.example/alice.jpg" }
            """, profile);
        BridgeJson.Equal("""{ "avatarUrl": "https://cdn.example/alice.jpg" }""", avatar);
    }
}
