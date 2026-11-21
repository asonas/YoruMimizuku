using System.Text.Json.Nodes;
using YoruMimizuku.Core.Tests;

namespace YoruMimizuku.App.Interop.Tests;

/// <summary>
/// Feed and thread pages as the views receive them. The XRPC bodies are the core tests'
/// fixtures (TimelineResponseTests, ThreadResponseTests); each expected value is the JSON
/// the former Swift bridge encoded for that body.
/// </summary>
public class FeedMappingTests
{
    private static CoreAccountClient Client(StubHttp http) => new(http.Xrpc());

    // TimelineResponseTests.Fixture: a post with images and an avatar, and a repost.
    private const string TimelineBody = """
    {
      "cursor": "next-page",
      "feed": [
        {
          "post": {
            "uri": "at://did:plc:alice/app.bsky.feed.post/aaa",
            "cid": "bafyreialice",
            "author": { "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice", "avatar": "https://cdn.example/alice.jpg" },
            "record": { "$type": "app.bsky.feed.post", "text": "hello timeline", "createdAt": "2026-06-04T12:00:00.000Z" },
            "replyCount": 1,
            "repostCount": 2,
            "likeCount": 3,
            "indexedAt": "2026-06-04T12:00:01.000Z",
            "embed": {
              "$type": "app.bsky.embed.images#view",
              "images": [
                { "thumb": "https://cdn.example/thumb1.jpg", "fullsize": "https://cdn.example/full1.jpg", "alt": "a cat", "aspectRatio": { "width": 1600, "height": 900 } },
                { "thumb": "https://cdn.example/thumb2.jpg", "fullsize": "https://cdn.example/full2.jpg", "alt": "" }
              ]
            }
          }
        },
        {
          "post": {
            "uri": "at://did:plc:carol/app.bsky.feed.post/ccc",
            "cid": "bafyrecarol",
            "author": { "did": "did:plc:carol", "handle": "carol.bsky.social" },
            "record": { "$type": "app.bsky.feed.post", "text": "reposted thing", "createdAt": "2026-06-04T11:00:00.000Z" },
            "indexedAt": "2026-06-04T11:30:00.000Z"
          },
          "reason": {
            "$type": "app.bsky.feed.defs#reasonRepost",
            "by": { "did": "did:plc:bob", "handle": "bob.bsky.social", "displayName": "Bob" },
            "indexedAt": "2026-06-04T11:45:00.000Z"
          }
        }
      ]
    }
    """;

    [Fact]
    public async Task TimelinePageMapsLikeTheBridge()
    {
        var http = new StubHttp(TimelineBody);

        var page = await Client(http).TimelineLoadAsync("c1");

        Assert.Equal("c1", http.Last.Query["cursor"]);
        BridgeJson.Equal("""
        {
          "cursor": "next-page",
          "posts": [
            {
              "id": "at://did:plc:alice/app.bsky.feed.post/aaa", "cid": "bafyreialice",
              "authorDisplayName": "Alice", "authorHandle": "alice.bsky.social", "avatarUrl": "https://cdn.example/alice.jpg",
              "body": "hello timeline", "segments": [ { "kind": "text", "text": "hello timeline" } ],
              "createdAt": "2026-06-04T12:00:00.000Z",
              "images": [
                { "thumbUrl": "https://cdn.example/thumb1.jpg", "fullsizeUrl": "https://cdn.example/full1.jpg", "alt": "a cat", "aspectRatio": 1.7777777777777777 },
                { "thumbUrl": "https://cdn.example/thumb2.jpg", "fullsizeUrl": "https://cdn.example/full2.jpg", "alt": "" }
              ],
              "replyCount": 1, "repostCount": 2, "likeCount": 3, "isLiked": false, "isReposted": false
            },
            {
              "id": "at://did:plc:carol/app.bsky.feed.post/ccc", "cid": "bafyrecarol",
              "authorDisplayName": "carol.bsky.social", "authorHandle": "carol.bsky.social",
              "body": "reposted thing", "segments": [ { "kind": "text", "text": "reposted thing" } ],
              "createdAt": "2026-06-04T11:00:00.000Z", "contextLabel": "Bob がリポスト", "images": [],
              "replyCount": 0, "repostCount": 0, "likeCount": 0, "isLiked": false, "isReposted": false
            }
          ]
        }
        """, page);
    }

    // Rows assembled from TimelineResponseTests' embed, label, facet, viewer and reply fixtures.
    private const string RichFeedBody = """
    {
      "feed": [
        {
          "post": {
            "uri": "at://did:plc:alice/app.bsky.feed.post/reply",
            "cid": "cid",
            "author": { "did": "did:plc:alice", "handle": "alice.bsky.social" },
            "record": {
              "$type": "app.bsky.feed.post",
              "text": "see https://example.com #swift cc @bob.bsky.social",
              "createdAt": "2026-06-04T12:00:00Z",
              "facets": [
                { "index": { "byteStart": 4, "byteEnd": 23 }, "features": [ { "$type": "app.bsky.richtext.facet#link", "uri": "https://example.com" } ] },
                { "index": { "byteStart": 24, "byteEnd": 30 }, "features": [ { "$type": "app.bsky.richtext.facet#tag", "tag": "swift" } ] },
                { "index": { "byteStart": 34, "byteEnd": 50 }, "features": [ { "$type": "app.bsky.richtext.facet#mention", "did": "did:plc:bob" } ] }
              ]
            },
            "indexedAt": "2026-06-04T12:00:01Z",
            "viewer": { "like": "at://did:plc:me/app.bsky.feed.like/abc", "repost": "at://did:plc:me/app.bsky.feed.repost/def" }
          },
          "reply": {
            "root": {
              "$type": "app.bsky.feed.defs#postView",
              "uri": "at://did:plc:bob/app.bsky.feed.post/root",
              "cid": "cidroot",
              "author": { "did": "did:plc:bob", "handle": "bob.bsky.social" },
              "record": { "$type": "app.bsky.feed.post", "text": "root", "createdAt": "2026-06-04T11:00:00Z" },
              "indexedAt": "2026-06-04T11:00:01Z"
            },
            "parent": {
              "$type": "app.bsky.feed.defs#postView",
              "uri": "at://did:plc:bob/app.bsky.feed.post/parent",
              "cid": "cidparent",
              "author": { "did": "did:plc:bob", "handle": "bob.bsky.social", "displayName": "Bob" },
              "record": { "$type": "app.bsky.feed.post", "text": "original question", "createdAt": "2026-06-04T11:30:00Z" },
              "indexedAt": "2026-06-04T11:30:01Z"
            }
          }
        },
        {
          "post": {
            "uri": "at://did:plc:alice/app.bsky.feed.post/lbl",
            "cid": "cid",
            "author": { "did": "did:plc:alice", "handle": "alice.bsky.social" },
            "record": { "$type": "app.bsky.feed.post", "text": "nsfw", "createdAt": "2026-06-04T12:00:00Z" },
            "indexedAt": "2026-06-04T12:00:01Z",
            "labels": [
              { "src": "did:plc:alice", "uri": "at://did:plc:alice/app.bsky.feed.post/lbl", "val": "porn", "cts": "2026-06-04T12:00:00Z" },
              { "src": "did:plc:labeler", "uri": "at://did:plc:labeler/x", "val": "spam", "neg": true, "cts": "2026-06-04T12:00:00Z" }
            ],
            "embed": {
              "$type": "app.bsky.embed.external#view",
              "external": {
                "uri": "https://www.ableton.com/ja/blog/satsuki/",
                "title": "Satsuki on her new EP",
                "description": "An interview with the artist.",
                "thumb": "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:x/bafkthumb@jpeg"
              }
            }
          }
        },
        {
          "post": {
            "uri": "at://did:plc:x/app.bsky.feed.post/x",
            "cid": "cid",
            "author": { "did": "did:plc:x", "handle": "x.bsky.social" },
            "record": { "$type": "app.bsky.feed.post", "text": "quote", "createdAt": "2026-06-04T12:00:00Z" },
            "indexedAt": "2026-06-04T12:00:01Z",
            "embed": {
              "$type": "app.bsky.embed.record#view",
              "record": {
                "$type": "app.bsky.embed.record#viewRecord",
                "uri": "at://did:plc:quoted/app.bsky.feed.post/qqq",
                "cid": "bafyquoted",
                "author": { "did": "did:plc:quoted", "handle": "quoted.bsky.social", "displayName": "Quoted Author", "avatar": "https://cdn.example/quoted.jpg" },
                "value": { "$type": "app.bsky.feed.post", "text": "quoted with pics", "createdAt": "2026-06-10T08:00:00.000Z" },
                "embeds": [
                  {
                    "$type": "app.bsky.embed.images#view",
                    "images": [ { "thumb": "https://cdn.example/q-thumb.jpg", "fullsize": "https://cdn.example/q-full.jpg", "alt": "" } ]
                  }
                ],
                "indexedAt": "2026-06-10T08:00:01.000Z"
              }
            }
          }
        },
        {
          "post": {
            "uri": "at://did:plc:x/app.bsky.feed.post/y",
            "cid": "cid",
            "author": { "did": "did:plc:x", "handle": "x.bsky.social" },
            "record": { "$type": "app.bsky.feed.post", "text": "video", "createdAt": "2026-06-04T12:00:00Z" },
            "indexedAt": "2026-06-04T12:00:01Z",
            "embed": {
              "$type": "app.bsky.embed.recordWithMedia#view",
              "record": {
                "$type": "app.bsky.embed.record#view",
                "record": {
                  "$type": "app.bsky.embed.record#viewRecord",
                  "uri": "at://did:plc:quoted/app.bsky.feed.post/qqq",
                  "cid": "bafyquoted",
                  "author": { "did": "did:plc:quoted", "handle": "quoted.bsky.social" },
                  "value": { "$type": "app.bsky.feed.post", "text": "the quoted text", "createdAt": "2026-06-10T08:00:00.000Z" },
                  "indexedAt": "2026-06-10T08:00:01.000Z"
                }
              },
              "media": {
                "$type": "app.bsky.embed.video#view",
                "cid": "bafyvideo",
                "playlist": "https://video.example/watch/playlist.m3u8",
                "thumbnail": "https://video.example/watch/thumbnail.jpg"
              }
            }
          }
        }
      ]
    }
    """;

    [Fact]
    public async Task AuthorFeedMapsSegmentsReplyParentEmbedsAndViewerStateLikeTheBridge()
    {
        var http = new StubHttp(RichFeedBody);

        var page = await Client(http).AuthorFeedLoadAsync("did:plc:alice");

        Assert.Equal("did:plc:alice", http.Last.Query["actor"]);
        BridgeJson.Equal("""
        {
          "posts": [
            {
              "id": "at://did:plc:alice/app.bsky.feed.post/reply", "cid": "cid",
              "authorDisplayName": "alice.bsky.social", "authorHandle": "alice.bsky.social",
              "body": "see https://example.com #swift cc @bob.bsky.social",
              "segments": [
                { "kind": "text", "text": "see " },
                { "kind": "link", "text": "https://example.com", "url": "https://example.com" },
                { "kind": "text", "text": " " },
                { "kind": "tag", "text": "#swift", "url": "https://bsky.app/hashtag/swift" },
                { "kind": "text", "text": " cc " },
                { "kind": "mention", "text": "@bob.bsky.social", "url": "https://bsky.app/profile/did:plc:bob" }
              ],
              "createdAt": "2026-06-04T12:00:00.000Z", "images": [],
              "replyParent": {
                "id": "at://did:plc:bob/app.bsky.feed.post/parent", "authorDisplayName": "Bob", "authorHandle": "bob.bsky.social",
                "body": "original question", "segments": [ { "kind": "text", "text": "original question" } ]
              },
              "replyCount": 0, "repostCount": 0, "likeCount": 0,
              "viewerLikeUri": "at://did:plc:me/app.bsky.feed.like/abc", "viewerRepostUri": "at://did:plc:me/app.bsky.feed.repost/def",
              "isLiked": true, "isReposted": true
            },
            {
              "id": "at://did:plc:alice/app.bsky.feed.post/lbl", "cid": "cid",
              "authorDisplayName": "alice.bsky.social", "authorHandle": "alice.bsky.social",
              "body": "nsfw", "segments": [ { "kind": "text", "text": "nsfw" } ],
              "createdAt": "2026-06-04T12:00:00.000Z", "mediaWarning": "adult", "images": [],
              "linkCard": {
                "url": "https://www.ableton.com/ja/blog/satsuki/", "title": "Satsuki on her new EP",
                "description": "An interview with the artist.",
                "thumbUrl": "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:x/bafkthumb@jpeg", "host": "ableton.com"
              },
              "replyCount": 0, "repostCount": 0, "likeCount": 0, "isLiked": false, "isReposted": false
            },
            {
              "id": "at://did:plc:x/app.bsky.feed.post/x", "cid": "cid",
              "authorDisplayName": "x.bsky.social", "authorHandle": "x.bsky.social",
              "body": "quote", "segments": [ { "kind": "text", "text": "quote" } ],
              "createdAt": "2026-06-04T12:00:00.000Z", "images": [],
              "quote": {
                "id": "at://did:plc:quoted/app.bsky.feed.post/qqq", "cid": "bafyquoted",
                "authorDisplayName": "Quoted Author", "authorHandle": "quoted.bsky.social", "avatarUrl": "https://cdn.example/quoted.jpg",
                "body": "quoted with pics", "createdAt": "2026-06-10T08:00:00.000Z",
                "images": [ { "thumbUrl": "https://cdn.example/q-thumb.jpg", "fullsizeUrl": "https://cdn.example/q-full.jpg", "alt": "" } ]
              },
              "replyCount": 0, "repostCount": 0, "likeCount": 0, "isLiked": false, "isReposted": false
            },
            {
              "id": "at://did:plc:x/app.bsky.feed.post/y", "cid": "cid",
              "authorDisplayName": "x.bsky.social", "authorHandle": "x.bsky.social",
              "body": "video", "segments": [ { "kind": "text", "text": "video" } ],
              "createdAt": "2026-06-04T12:00:00.000Z", "images": [],
              "video": { "thumbUrl": "https://video.example/watch/thumbnail.jpg", "playlistUrl": "https://video.example/watch/playlist.m3u8" },
              "quote": {
                "id": "at://did:plc:quoted/app.bsky.feed.post/qqq", "cid": "bafyquoted",
                "authorDisplayName": "quoted.bsky.social", "authorHandle": "quoted.bsky.social",
                "body": "the quoted text", "createdAt": "2026-06-10T08:00:00.000Z", "images": []
              },
              "replyCount": 0, "repostCount": 0, "likeCount": 0, "isLiked": false, "isReposted": false
            }
          ]
        }
        """, page);
    }

    // ThreadResponseTests.DecodesFullAncestorChain.
    private const string AncestorChainBody = """
    {
      "thread": {
        "$type": "app.bsky.feed.defs#threadViewPost",
        "post": {
          "uri": "at://did:plc:c/app.bsky.feed.post/leaf", "cid": "cidc",
          "author": { "did": "did:plc:c", "handle": "carol.bsky.social" },
          "record": { "text": "孫", "createdAt": "2026-06-04T12:10:00.000Z" },
          "indexedAt": "2026-06-04T12:10:01.000Z"
        },
        "parent": {
          "$type": "app.bsky.feed.defs#threadViewPost",
          "post": {
            "uri": "at://did:plc:b/app.bsky.feed.post/mid", "cid": "cidb",
            "author": { "did": "did:plc:b", "handle": "bob.bsky.social" },
            "record": { "text": "子", "createdAt": "2026-06-04T12:05:00.000Z" },
            "indexedAt": "2026-06-04T12:05:01.000Z"
          },
          "parent": {
            "$type": "app.bsky.feed.defs#threadViewPost",
            "post": {
              "uri": "at://did:plc:a/app.bsky.feed.post/root", "cid": "cida",
              "author": { "did": "did:plc:a", "handle": "alice.bsky.social" },
              "record": { "text": "親", "createdAt": "2026-06-04T12:00:00.000Z" },
              "indexedAt": "2026-06-04T12:00:01.000Z"
            }
          }
        }
      }
    }
    """;

    /// The ReplyParentDto carries one level: the bridge drops the rest of the chain.
    [Fact]
    public async Task ThreadFocusCarriesOnlyItsImmediateParent()
    {
        var http = new StubHttp(AncestorChainBody);

        var thread = await Client(http).ThreadLoadAsync("at://did:plc:c/app.bsky.feed.post/leaf");

        Assert.Equal("at://did:plc:c/app.bsky.feed.post/leaf", http.Last.Query["uri"]);
        BridgeJson.Equal("""
        {
          "focus": {
            "id": "at://did:plc:c/app.bsky.feed.post/leaf", "cid": "cidc",
            "authorDisplayName": "carol.bsky.social", "authorHandle": "carol.bsky.social",
            "body": "孫", "segments": [ { "kind": "text", "text": "孫" } ],
            "createdAt": "2026-06-04T12:10:00.000Z", "images": [],
            "replyParent": {
              "id": "at://did:plc:b/app.bsky.feed.post/mid", "authorDisplayName": "bob.bsky.social", "authorHandle": "bob.bsky.social",
              "body": "子", "segments": [ { "kind": "text", "text": "子" } ]
            },
            "replyCount": 0, "repostCount": 0, "likeCount": 0, "isLiked": false, "isReposted": false
          },
          "replies": []
        }
        """, thread);
    }

    /// The bridge builds the reply tree to depth 3; a node there keeps no replies.
    [Fact]
    public async Task ThreadRepliesStopAtDepthThree()
    {
        // The anchor of DecodesChildRepliesSkippingNotFoundAndBlocked, with a five-deep reply chain.
        var replies = new JsonArray();
        for (var depth = 4; depth >= 0; depth--)
        {
            var node = new JsonObject
            {
                ["$type"] = "app.bsky.feed.defs#threadViewPost",
                ["post"] = Post($"at://did:plc:b/app.bsky.feed.post/r{depth}", $"返信{depth}"),
                ["replies"] = replies,
            };
            replies = new JsonArray(node);
        }
        var body = new JsonObject
        {
            ["thread"] = new JsonObject
            {
                ["post"] = Post("at://did:plc:a/app.bsky.feed.post/anchor", "起点"),
                ["replies"] = replies,
            },
        };
        var http = new StubHttp(body.ToJsonString());

        var thread = await Client(http).ThreadLoadAsync("at://did:plc:a/app.bsky.feed.post/anchor");

        var path = new List<ThreadNodeDto>();
        for (var level = thread.Replies; level.Count > 0; level = level[0].Replies) path.Add(Assert.Single(level));
        Assert.Equal([0, 1, 2, 3], path.Select(n => n.Depth));
        Assert.Equal(["返信0", "返信1", "返信2", "返信3"], path.Select(n => n.Post.Body));
        Assert.All(path, n => Assert.Null(n.Post.ReplyParent));
    }

    private static JsonObject Post(string uri, string text) => new()
    {
        ["uri"] = uri,
        ["cid"] = "cid",
        ["author"] = new JsonObject { ["did"] = "did:plc:b", ["handle"] = "bob.bsky.social" },
        ["record"] = new JsonObject { ["text"] = text, ["createdAt"] = "2026-06-04T12:05:00.000Z" },
        ["indexedAt"] = "2026-06-04T12:05:01.000Z",
    };
}
