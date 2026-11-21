using System.Text.Json;

namespace YoruMimizuku.Core.Tests;

public class TimelineResponseTests
{
    /// Trimmed `app.bsky.feed.getTimeline` response: one plain post and one that
    /// surfaced via a repost (carrying a `reason`).
    private const string Fixture = """
    {
      "cursor": "next-page",
      "feed": [
        {
          "post": {
            "uri": "at://did:plc:alice/app.bsky.feed.post/aaa",
            "cid": "bafyreialice",
            "author": {
              "did": "did:plc:alice",
              "handle": "alice.bsky.social",
              "displayName": "Alice",
              "avatar": "https://cdn.example/alice.jpg"
            },
            "record": {
              "$type": "app.bsky.feed.post",
              "text": "hello timeline",
              "createdAt": "2026-06-04T12:00:00.000Z"
            },
            "replyCount": 1,
            "repostCount": 2,
            "likeCount": 3,
            "indexedAt": "2026-06-04T12:00:01.000Z",
            "embed": {
              "$type": "app.bsky.embed.images#view",
              "images": [
                {
                  "thumb": "https://cdn.example/thumb1.jpg",
                  "fullsize": "https://cdn.example/full1.jpg",
                  "alt": "a cat",
                  "aspectRatio": { "width": 1600, "height": 900 }
                },
                {
                  "thumb": "https://cdn.example/thumb2.jpg",
                  "fullsize": "https://cdn.example/full2.jpg",
                  "alt": ""
                }
              ]
            }
          }
        },
        {
          "post": {
            "uri": "at://did:plc:carol/app.bsky.feed.post/ccc",
            "cid": "bafyrecarol",
            "author": {
              "did": "did:plc:carol",
              "handle": "carol.bsky.social"
            },
            "record": {
              "$type": "app.bsky.feed.post",
              "text": "reposted thing",
              "createdAt": "2026-06-04T11:00:00.000Z"
            },
            "indexedAt": "2026-06-04T11:30:00.000Z"
          },
          "reason": {
            "$type": "app.bsky.feed.defs#reasonRepost",
            "by": {
              "did": "did:plc:bob",
              "handle": "bob.bsky.social",
              "displayName": "Bob"
            },
            "indexedAt": "2026-06-04T11:45:00.000Z"
          }
        }
      ]
    }
    """;

    private static TimelineResponse DecodeFixture() => TimelineResponse.FromJson(JsonElement.Parse(Fixture));

    /// The author's verification badge comes from `verification.verifiedStatus`.
    [Fact]
    public void AuthorVerificationDecodesFromVerifiedStatus()
    {
        var body = """
        [
          { "did": "did:plc:a", "handle": "a.example", "verification": { "verifications": [], "verifiedStatus": "valid", "trustedVerifierStatus": "none" } },
          { "did": "did:plc:b", "handle": "b.example", "verification": { "verifications": [], "verifiedStatus": "invalid", "trustedVerifierStatus": "none" } },
          { "did": "did:plc:c", "handle": "c.example" }
        ]
        """;

        var authors = JsonElement.Parse(body).EnumerateArray().Select(ProfileViewBasic.FromJson);

        Assert.Equal([true, false, false], authors.Select(a => a.IsVerified));
    }

    /// Custom feeds (`getFeed`) mark a feed's pinned post with `reasonPin`,
    /// which carries no reposter. The page must still decode.
    [Fact]
    public void PinnedPostReasonDecodesWithoutARepost()
    {
        var body = """
        {
          "feed": [
            {
              "post": {
                "uri": "at://did:plc:alice/app.bsky.feed.post/pin",
                "cid": "bafy",
                "author": { "did": "did:plc:alice", "handle": "alice.bsky.social" },
                "record": { "$type": "app.bsky.feed.post", "text": "pinned", "createdAt": "2026-06-04T12:00:00.000Z" },
                "indexedAt": "2026-06-04T12:00:01.000Z"
              },
              "reason": { "$type": "app.bsky.feed.defs#reasonPin" }
            }
          ]
        }
        """;

        var response = TimelineResponse.FromJson(JsonElement.Parse(body));

        var item = Assert.Single(response.Feed);
        Assert.Equal("at://did:plc:alice/app.bsky.feed.post/pin", item.Post.Uri);
        Assert.Null(item.Reason);
    }

    [Fact]
    public void DecodesTimelineWithCursorAndTwoItems()
    {
        var response = DecodeFixture();

        Assert.Equal("next-page", response.Cursor);
        Assert.Equal(2, response.Feed.Count);
    }

    [Fact]
    public void DecodesPlainPostFields()
    {
        var item = DecodeFixture().Feed[0];

        Assert.Null(item.Reason);
        Assert.Equal("at://did:plc:alice/app.bsky.feed.post/aaa", item.Post.Uri);
        Assert.Equal("bafyreialice", item.Post.Cid);
        Assert.Equal("alice.bsky.social", item.Post.Author.Handle);
        Assert.Equal("Alice", item.Post.Author.DisplayName);
        Assert.Equal("https://cdn.example/alice.jpg", item.Post.Author.Avatar);
        Assert.Equal("hello timeline", item.Post.Record.Text);
        Assert.Equal("2026-06-04T12:00:00.000Z", item.Post.Record.CreatedAt);
        Assert.Equal(1, item.Post.ReplyCount);
        Assert.Equal(2, item.Post.RepostCount);
        Assert.Equal(3, item.Post.LikeCount);
    }

    [Fact]
    public void DecodesImageEmbed()
    {
        var images = DecodeFixture().Feed[0].Post.Embed!.Images;

        Assert.Equal(2, images.Count);
        Assert.Equal("https://cdn.example/thumb1.jpg", images[0].Thumb);
        Assert.Equal("https://cdn.example/full1.jpg", images[0].Fullsize);
        Assert.Equal("a cat", images[0].Alt);
        Assert.Equal("", images[1].Alt);
    }

    [Fact]
    public void DecodesImageAspectRatio()
    {
        var images = DecodeFixture().Feed[0].Post.Embed!.Images;

        Assert.Equal(new ImageAspectRatio(1600, 900), images[0].AspectRatio);
    }

    [Fact]
    public void ImageWithoutAspectRatioHasNilAspectRatio()
    {
        var images = DecodeFixture().Feed[0].Post.Embed!.Images;

        Assert.Null(images[1].AspectRatio);
    }

    [Fact]
    public void PostWithoutEmbedHasNilEmbed()
    {
        Assert.Null(DecodeFixture().Feed[1].Post.Embed);
    }

    [Fact]
    public void DecodesPostLabels()
    {
        var json = """
        {
          "uri": "at://did:plc:alice/app.bsky.feed.post/lbl",
          "cid": "cid",
          "author": { "did": "did:plc:alice", "handle": "alice.bsky.social" },
          "record": { "$type": "app.bsky.feed.post", "text": "nsfw", "createdAt": "2026-06-04T12:00:00Z" },
          "indexedAt": "2026-06-04T12:00:01Z",
          "labels": [
            { "src": "did:plc:alice", "uri": "at://did:plc:alice/app.bsky.feed.post/lbl", "val": "porn", "cts": "2026-06-04T12:00:00Z" },
            { "src": "did:plc:labeler", "uri": "at://did:plc:labeler/x", "val": "spam", "neg": true, "cts": "2026-06-04T12:00:00Z" }
          ]
        }
        """;

        var post = PostView.FromJson(JsonElement.Parse(json));

        Assert.Equal(
            [new Label("porn", "did:plc:alice", null), new Label("spam", "did:plc:labeler", true)],
            post.Labels);
    }

    [Fact]
    public void PostWithoutLabelsHasEmptyLabels()
    {
        Assert.Empty(DecodeFixture().Feed[0].Post.Labels);
    }

    [Fact]
    public void DecodesReplyParent()
    {
        var json = """
        {
          "post": {
            "uri": "at://did:plc:alice/app.bsky.feed.post/reply",
            "cid": "cid",
            "author": { "did": "did:plc:alice", "handle": "alice.bsky.social" },
            "record": { "$type": "app.bsky.feed.post", "text": "agreed!", "createdAt": "2026-06-04T12:00:00Z" },
            "indexedAt": "2026-06-04T12:00:01Z"
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
        }
        """;

        var item = FeedViewPost.FromJson(JsonElement.Parse(json));

        Assert.Equal("bob.bsky.social", item.Reply?.Parent?.Author.Handle);
        Assert.Equal("original question", item.Reply?.Parent?.Record.Text);
    }

    [Fact]
    public void ReplyWithNotFoundParentDecodesToNilParent()
    {
        var json = """
        {
          "post": {
            "uri": "at://did:plc:alice/app.bsky.feed.post/reply",
            "cid": "cid",
            "author": { "did": "did:plc:alice", "handle": "alice.bsky.social" },
            "record": { "$type": "app.bsky.feed.post", "text": "reply", "createdAt": "2026-06-04T12:00:00Z" },
            "indexedAt": "2026-06-04T12:00:01Z"
          },
          "reply": {
            "parent": { "$type": "app.bsky.feed.defs#notFoundPost", "uri": "at://x", "notFound": true }
          }
        }
        """;

        var item = FeedViewPost.FromJson(JsonElement.Parse(json));

        Assert.NotNull(item.Reply);
        Assert.Null(item.Reply.Parent);
    }

    [Fact]
    public void DecodesViewerLikeAndRepostState()
    {
        var json = """
        {
          "uri": "at://did:plc:x/app.bsky.feed.post/x",
          "cid": "cid",
          "author": { "did": "did:plc:x", "handle": "x.bsky.social" },
          "record": { "$type": "app.bsky.feed.post", "text": "hi", "createdAt": "2026-06-04T12:00:00Z" },
          "indexedAt": "2026-06-04T12:00:01Z",
          "viewer": {
            "like": "at://did:plc:me/app.bsky.feed.like/abc",
            "repost": "at://did:plc:me/app.bsky.feed.repost/def"
          }
        }
        """;

        var post = PostView.FromJson(JsonElement.Parse(json));

        Assert.Equal("at://did:plc:me/app.bsky.feed.like/abc", post.Viewer?.Like);
        Assert.Equal("at://did:plc:me/app.bsky.feed.repost/def", post.Viewer?.Repost);
    }

    [Fact]
    public void ViewerStateOmitsUnsetFields()
    {
        var json = """
        {
          "uri": "at://did:plc:x/app.bsky.feed.post/x",
          "cid": "cid",
          "author": { "did": "did:plc:x", "handle": "x.bsky.social" },
          "record": { "$type": "app.bsky.feed.post", "text": "hi", "createdAt": "2026-06-04T12:00:00Z" },
          "indexedAt": "2026-06-04T12:00:01Z",
          "viewer": { "threadMuted": false, "embeddingDisabled": false }
        }
        """;

        var post = PostView.FromJson(JsonElement.Parse(json));

        Assert.Equal(new PostViewerState(null, null), post.Viewer);
    }

    /// A record embed (different shape) must not break decoding; images is empty.
    [Fact]
    public void NonImageEmbedDecodesToEmptyImages()
    {
        var json = """
        {
          "uri": "at://did:plc:x/app.bsky.feed.post/x",
          "cid": "cid",
          "author": { "did": "did:plc:x", "handle": "x.bsky.social" },
          "record": { "$type": "app.bsky.feed.post", "text": "quote", "createdAt": "2026-06-04T12:00:00Z" },
          "indexedAt": "2026-06-04T12:00:01Z",
          "embed": { "$type": "app.bsky.embed.record#view", "record": { "uri": "at://did:plc:y/app.bsky.feed.post/y" } }
        }
        """;

        var post = PostView.FromJson(JsonElement.Parse(json));

        Assert.NotNull(post.Embed);
        Assert.Empty(post.Embed.Images);
    }

    [Fact]
    public void DecodesExternalEmbed()
    {
        var json = """
        {
          "uri": "at://did:plc:x/app.bsky.feed.post/x",
          "cid": "cid",
          "author": { "did": "did:plc:x", "handle": "x.bsky.social" },
          "record": { "$type": "app.bsky.feed.post", "text": "link", "createdAt": "2026-06-04T12:00:00Z" },
          "indexedAt": "2026-06-04T12:00:01Z",
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
        """;

        var post = PostView.FromJson(JsonElement.Parse(json));

        Assert.Equal(
            new EmbedExternal(
                "https://www.ableton.com/ja/blog/satsuki/",
                "Satsuki on her new EP",
                "An interview with the artist.",
                "https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:x/bafkthumb@jpeg"),
            post.Embed?.External);
        Assert.Empty(post.Embed!.Images);
    }

    [Fact]
    public void ExternalEmbedWithoutThumbDecodes()
    {
        var json = """
        {
          "uri": "at://did:plc:x/app.bsky.feed.post/x",
          "cid": "cid",
          "author": { "did": "did:plc:x", "handle": "x.bsky.social" },
          "record": { "$type": "app.bsky.feed.post", "text": "link", "createdAt": "2026-06-04T12:00:00Z" },
          "indexedAt": "2026-06-04T12:00:01Z",
          "embed": {
            "$type": "app.bsky.embed.external#view",
            "external": {
              "uri": "https://example.com/article",
              "title": "Article",
              "description": ""
            }
          }
        }
        """;

        var post = PostView.FromJson(JsonElement.Parse(json));

        Assert.Equal(new EmbedExternal("https://example.com/article", "Article", "", null), post.Embed?.External);
    }

    [Fact]
    public void ImageEmbedHasNilExternal()
    {
        Assert.Null(DecodeFixture().Feed[0].Post.Embed!.External);
    }

    [Fact]
    public void DecodesRepostReasonAndOptionalAuthorFields()
    {
        var item = DecodeFixture().Feed[1];

        Assert.Null(item.Post.Author.DisplayName);
        Assert.Null(item.Post.Author.Avatar);
        Assert.Null(item.Post.ReplyCount);
        Assert.Equal("bob.bsky.social", item.Reason?.By.Handle);
        Assert.Equal("Bob", item.Reason?.By.DisplayName);
        Assert.Equal("2026-06-04T11:45:00.000Z", item.Reason?.IndexedAt);
    }

    [Fact]
    public void DecodesRecordFacetsForLinkTagAndMention()
    {
        var json = """
        {
          "$type": "app.bsky.feed.post",
          "text": "see https://example.com #swift cc @bob.bsky.social",
          "createdAt": "2026-06-04T12:00:00Z",
          "facets": [
            {
              "index": { "byteStart": 4, "byteEnd": 23 },
              "features": [
                { "$type": "app.bsky.richtext.facet#link", "uri": "https://example.com" }
              ]
            },
            {
              "index": { "byteStart": 24, "byteEnd": 30 },
              "features": [
                { "$type": "app.bsky.richtext.facet#tag", "tag": "swift" }
              ]
            },
            {
              "index": { "byteStart": 34, "byteEnd": 50 },
              "features": [
                { "$type": "app.bsky.richtext.facet#mention", "did": "did:plc:bob" }
              ]
            }
          ]
        }
        """;

        var record = PostRecord.FromJson(JsonElement.Parse(json));

        Assert.Equal(3, record.Facets.Count);
        Assert.Equal(4, record.Facets[0].ByteStart);
        Assert.Equal(23, record.Facets[0].ByteEnd);
        Assert.Equal(new FacetFeature.Link("https://example.com"), Assert.Single(record.Facets[0].Features));
        Assert.Equal(new FacetFeature.Tag("swift"), Assert.Single(record.Facets[1].Features));
        Assert.Equal(new FacetFeature.Mention("did:plc:bob"), Assert.Single(record.Facets[2].Features));
    }

    [Fact]
    public void RecordWithoutFacetsDecodesToEmpty()
    {
        var json = """
        { "$type": "app.bsky.feed.post", "text": "plain", "createdAt": "2026-06-04T12:00:00Z" }
        """;

        Assert.Empty(PostRecord.FromJson(JsonElement.Parse(json)).Facets);
    }

    [Fact]
    public void DecodesVideoEmbed()
    {
        var json = """
        {
          "$type": "app.bsky.embed.video#view",
          "cid": "bafyvideo",
          "playlist": "https://video.example/watch/playlist.m3u8",
          "thumbnail": "https://video.example/watch/thumbnail.jpg",
          "alt": "a dog running",
          "aspectRatio": { "width": 1280, "height": 720 }
        }
        """;

        var embed = PostEmbed.FromJson(JsonElement.Parse(json));

        Assert.Equal(
            new EmbedVideo(
                "https://video.example/watch/playlist.m3u8",
                "https://video.example/watch/thumbnail.jpg",
                "a dog running",
                new ImageAspectRatio(1280, 720)),
            embed.Video);
        Assert.Empty(embed.Images);
        Assert.Null(embed.External);
    }

    [Fact]
    public void DecodesRecordEmbedAsQuotedPost()
    {
        var json = """
        {
          "$type": "app.bsky.embed.record#view",
          "record": {
            "$type": "app.bsky.embed.record#viewRecord",
            "uri": "at://did:plc:quoted/app.bsky.feed.post/qqq",
            "cid": "bafyquoted",
            "author": {
              "did": "did:plc:quoted",
              "handle": "quoted.bsky.social",
              "displayName": "Quoted Author",
              "avatar": "https://cdn.example/quoted.jpg"
            },
            "value": {
              "$type": "app.bsky.feed.post",
              "text": "the quoted text",
              "createdAt": "2026-06-10T08:00:00.000Z"
            },
            "indexedAt": "2026-06-10T08:00:01.000Z"
          }
        }
        """;

        var record = PostEmbed.FromJson(JsonElement.Parse(json)).Record;

        Assert.NotNull(record);
        Assert.Equal("at://did:plc:quoted/app.bsky.feed.post/qqq", record.Uri);
        Assert.Equal("bafyquoted", record.Cid);
        Assert.Equal("quoted.bsky.social", record.Author.Handle);
        Assert.Equal("the quoted text", record.Value.Text);
        Assert.Equal("2026-06-10T08:00:00.000Z", record.Value.CreatedAt);
        Assert.Empty(record.Embeds);
    }

    [Fact]
    public void NotFoundQuotedRecordDecodesToNilRecord()
    {
        var json = """
        {
          "$type": "app.bsky.embed.record#view",
          "record": {
            "$type": "app.bsky.embed.record#viewNotFound",
            "uri": "at://did:plc:gone/app.bsky.feed.post/zzz",
            "notFound": true
          }
        }
        """;

        Assert.Null(PostEmbed.FromJson(JsonElement.Parse(json)).Record);
    }

    [Fact]
    public void NonPostQuotedRecordDecodesToNilRecord()
    {
        var json = """
        {
          "$type": "app.bsky.embed.record#view",
          "record": {
            "$type": "app.bsky.graph.defs#listView",
            "uri": "at://did:plc:alice/app.bsky.graph.list/lll",
            "cid": "bafylist",
            "name": "my list",
            "purpose": "app.bsky.graph.defs#curatelist",
            "indexedAt": "2026-06-10T08:00:00.000Z"
          }
        }
        """;

        Assert.Null(PostEmbed.FromJson(JsonElement.Parse(json)).Record);
    }

    [Fact]
    public void DecodesRecordWithMediaImages()
    {
        var json = """
        {
          "$type": "app.bsky.embed.recordWithMedia#view",
          "record": {
            "$type": "app.bsky.embed.record#view",
            "record": {
              "$type": "app.bsky.embed.record#viewRecord",
              "uri": "at://did:plc:quoted/app.bsky.feed.post/qqq",
              "cid": "bafyquoted",
              "author": { "did": "did:plc:quoted", "handle": "quoted.bsky.social" },
              "value": {
                "$type": "app.bsky.feed.post",
                "text": "the quoted text",
                "createdAt": "2026-06-10T08:00:00.000Z"
              },
              "indexedAt": "2026-06-10T08:00:01.000Z"
            }
          },
          "media": {
            "$type": "app.bsky.embed.images#view",
            "images": [
              { "thumb": "https://cdn.example/m-thumb.jpg", "fullsize": "https://cdn.example/m-full.jpg", "alt": "media" }
            ]
          }
        }
        """;

        var embed = PostEmbed.FromJson(JsonElement.Parse(json));

        Assert.Equal("https://cdn.example/m-thumb.jpg", Assert.Single(embed.Images).Thumb);
        Assert.Equal("at://did:plc:quoted/app.bsky.feed.post/qqq", embed.Record?.Uri);
        Assert.Equal("the quoted text", embed.Record?.Value.Text);
    }

    [Fact]
    public void DecodesRecordWithMediaVideo()
    {
        var json = """
        {
          "$type": "app.bsky.embed.recordWithMedia#view",
          "record": {
            "$type": "app.bsky.embed.record#view",
            "record": {
              "$type": "app.bsky.embed.record#viewRecord",
              "uri": "at://did:plc:quoted/app.bsky.feed.post/qqq",
              "cid": "bafyquoted",
              "author": { "did": "did:plc:quoted", "handle": "quoted.bsky.social" },
              "value": {
                "$type": "app.bsky.feed.post",
                "text": "the quoted text",
                "createdAt": "2026-06-10T08:00:00.000Z"
              },
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
        """;

        var embed = PostEmbed.FromJson(JsonElement.Parse(json));

        Assert.Equal("https://video.example/watch/playlist.m3u8", embed.Video?.Playlist);
        Assert.Equal("the quoted text", embed.Record?.Value.Text);
        Assert.Empty(embed.Images);
    }

    [Fact]
    public void QuotedRecordCarriesItsOwnImageEmbeds()
    {
        var json = """
        {
          "$type": "app.bsky.embed.record#view",
          "record": {
            "$type": "app.bsky.embed.record#viewRecord",
            "uri": "at://did:plc:quoted/app.bsky.feed.post/qqq",
            "cid": "bafyquoted",
            "author": { "did": "did:plc:quoted", "handle": "quoted.bsky.social" },
            "value": {
              "$type": "app.bsky.feed.post",
              "text": "quoted with pics",
              "createdAt": "2026-06-10T08:00:00.000Z"
            },
            "embeds": [
              {
                "$type": "app.bsky.embed.images#view",
                "images": [
                  { "thumb": "https://cdn.example/q-thumb.jpg", "fullsize": "https://cdn.example/q-full.jpg", "alt": "" }
                ]
              }
            ],
            "indexedAt": "2026-06-10T08:00:01.000Z"
          }
        }
        """;

        var record = PostEmbed.FromJson(JsonElement.Parse(json)).Record;

        Assert.NotNull(record);
        var quotedEmbed = Assert.Single(record.Embeds);
        Assert.Equal("https://cdn.example/q-thumb.jpg", quotedEmbed.Images[0].Thumb);
    }

    [Fact]
    public void UnknownFacetFeatureIsDropped()
    {
        var json = """
        {
          "$type": "app.bsky.feed.post",
          "text": "x",
          "createdAt": "2026-06-04T12:00:00Z",
          "facets": [
            {
              "index": { "byteStart": 0, "byteEnd": 1 },
              "features": [ { "$type": "app.bsky.richtext.facet#unknownFuture", "foo": "bar" } ]
            }
          ]
        }
        """;

        var record = PostRecord.FromJson(JsonElement.Parse(json));

        Assert.Empty(Assert.Single(record.Facets).Features);
    }
}
