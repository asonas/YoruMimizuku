using System.Text.Json;

namespace YoruMimizuku.Core.Tests;

public class ThreadResponseTests
{
    [Fact]
    public void DecodesFocusedPostWithImmediateParent()
    {
        var body = """
        {
          "thread": {
            "$type": "app.bsky.feed.defs#threadViewPost",
            "post": {
              "uri": "at://did:plc:bob/app.bsky.feed.post/reply",
              "cid": "bafyreibob",
              "author": { "did": "did:plc:bob", "handle": "bob.bsky.social", "displayName": "Bob" },
              "record": { "text": "返信です", "createdAt": "2026-06-04T12:05:00.000Z" },
              "indexedAt": "2026-06-04T12:05:01.000Z"
            },
            "parent": {
              "$type": "app.bsky.feed.defs#threadViewPost",
              "post": {
                "uri": "at://did:plc:alice/app.bsky.feed.post/root",
                "cid": "bafyreialice",
                "author": { "did": "did:plc:alice", "handle": "alice.bsky.social", "displayName": "Alice" },
                "record": { "text": "親の投稿", "createdAt": "2026-06-04T12:00:00.000Z" },
                "indexedAt": "2026-06-04T12:00:01.000Z"
              }
            }
          }
        }
        """;

        var response = ThreadResponse.FromJson(JsonElement.Parse(body));

        Assert.Equal("bob.bsky.social", response.Thread.Post.Author.Handle);
        Assert.Equal("alice.bsky.social", response.Thread.ParentPost?.Author.Handle);
        Assert.Equal("親の投稿", response.Thread.ParentPost?.Record.Text);
    }

    [Fact]
    public void DecodesFullAncestorChain()
    {
        var body = """
        {
          "thread": {
            "$type": "app.bsky.feed.defs#threadViewPost",
            "post": {
              "uri": "at://did:plc:c/app.bsky.feed.post/leaf",
              "cid": "cidc",
              "author": { "did": "did:plc:c", "handle": "carol.bsky.social" },
              "record": { "text": "孫", "createdAt": "2026-06-04T12:10:00.000Z" },
              "indexedAt": "2026-06-04T12:10:01.000Z"
            },
            "parent": {
              "$type": "app.bsky.feed.defs#threadViewPost",
              "post": {
                "uri": "at://did:plc:b/app.bsky.feed.post/mid",
                "cid": "cidb",
                "author": { "did": "did:plc:b", "handle": "bob.bsky.social" },
                "record": { "text": "子", "createdAt": "2026-06-04T12:05:00.000Z" },
                "indexedAt": "2026-06-04T12:05:01.000Z"
              },
              "parent": {
                "$type": "app.bsky.feed.defs#threadViewPost",
                "post": {
                  "uri": "at://did:plc:a/app.bsky.feed.post/root",
                  "cid": "cida",
                  "author": { "did": "did:plc:a", "handle": "alice.bsky.social" },
                  "record": { "text": "親", "createdAt": "2026-06-04T12:00:00.000Z" },
                  "indexedAt": "2026-06-04T12:00:01.000Z"
                }
              }
            }
          }
        }
        """;

        var thread = ThreadResponse.FromJson(JsonElement.Parse(body)).Thread;

        Assert.Equal("carol.bsky.social", thread.Post.Author.Handle);
        Assert.Equal("bob.bsky.social", thread.Parent?.Post.Author.Handle);
        Assert.Equal("alice.bsky.social", thread.Parent?.Parent?.Post.Author.Handle);
        Assert.Null(thread.Parent?.Parent?.Parent);
    }

    [Fact]
    public void ParentIsNilForNotFoundOrAbsentParent()
    {
        var body = """
        {
          "thread": {
            "$type": "app.bsky.feed.defs#threadViewPost",
            "post": {
              "uri": "at://did:plc:alice/app.bsky.feed.post/root",
              "cid": "bafyreialice",
              "author": { "did": "did:plc:alice", "handle": "alice.bsky.social" },
              "record": { "text": "起点", "createdAt": "2026-06-04T12:00:00.000Z" },
              "indexedAt": "2026-06-04T12:00:01.000Z"
            },
            "parent": {
              "$type": "app.bsky.feed.defs#notFoundPost",
              "uri": "at://did:plc:ghost/app.bsky.feed.post/gone",
              "notFound": true
            }
          }
        }
        """;

        var thread = ThreadResponse.FromJson(JsonElement.Parse(body)).Thread;

        Assert.Equal("alice.bsky.social", thread.Post.Author.Handle);
        Assert.Null(thread.ParentPost);
    }

    [Fact]
    public void DecodesChildRepliesSkippingNotFoundAndBlocked()
    {
        var body = """
        {
          "thread": {
            "$type": "app.bsky.feed.defs#threadViewPost",
            "post": {
              "uri": "at://did:plc:a/app.bsky.feed.post/anchor",
              "cid": "cida",
              "author": { "did": "did:plc:a", "handle": "alice.bsky.social" },
              "record": { "text": "起点", "createdAt": "2026-06-04T12:00:00.000Z" },
              "indexedAt": "2026-06-04T12:00:01.000Z"
            },
            "replies": [
              {
                "$type": "app.bsky.feed.defs#threadViewPost",
                "post": {
                  "uri": "at://did:plc:b/app.bsky.feed.post/b",
                  "cid": "cidb",
                  "author": { "did": "did:plc:b", "handle": "bob.bsky.social" },
                  "record": { "text": "返信B", "createdAt": "2026-06-04T12:05:00.000Z" },
                  "indexedAt": "2026-06-04T12:05:01.000Z"
                },
                "replies": [
                  {
                    "$type": "app.bsky.feed.defs#threadViewPost",
                    "post": {
                      "uri": "at://did:plc:c/app.bsky.feed.post/c",
                      "cid": "cidc",
                      "author": { "did": "did:plc:c", "handle": "carol.bsky.social" },
                      "record": { "text": "返信C", "createdAt": "2026-06-04T12:06:00.000Z" },
                      "indexedAt": "2026-06-04T12:06:01.000Z"
                    }
                  }
                ]
              },
              {
                "$type": "app.bsky.feed.defs#notFoundPost",
                "uri": "at://did:plc:ghost/app.bsky.feed.post/gone",
                "notFound": true
              },
              {
                "$type": "app.bsky.feed.defs#blockedPost",
                "uri": "at://did:plc:blk/app.bsky.feed.post/blk",
                "blocked": true,
                "author": { "did": "did:plc:blocker" }
              },
              {
                "$type": "app.bsky.feed.defs#threadViewPost",
                "post": {
                  "uri": "at://did:plc:d/app.bsky.feed.post/d",
                  "cid": "cidd",
                  "author": { "did": "did:plc:d", "handle": "dave.bsky.social" },
                  "record": { "text": "返信D", "createdAt": "2026-06-04T12:07:00.000Z" },
                  "indexedAt": "2026-06-04T12:07:01.000Z"
                }
              }
            ]
          }
        }
        """;

        var thread = ThreadResponse.FromJson(JsonElement.Parse(body)).Thread;

        // notFound and blocked children dropped: B and D remain, in server order.
        Assert.Equal(["bob.bsky.social", "dave.bsky.social"], thread.Replies.Select(r => r.Post.Author.Handle));
        // Nested reply under B.
        Assert.Equal("carol.bsky.social", Assert.Single(thread.Replies[0].Replies).Post.Author.Handle);
        // A leaf reply has no children.
        Assert.Empty(thread.Replies[1].Replies);
    }
}
