using System.Text.Json;

namespace YoruMimizuku.Core.Tests;

public class NotificationsResponseTests
{
    /// Trimmed `app.bsky.notification.listNotifications` response covering a like
    /// (record carries no text), a reply (record is a post with text), a follow
    /// (no reasonSubject), and an unknown reason that must not break decoding.
    private const string Fixture = """
    {
      "cursor": "next-page",
      "notifications": [
        {
          "uri": "at://did:plc:bob/app.bsky.feed.like/aaa",
          "cid": "cidlike",
          "author": {
            "did": "did:plc:bob",
            "handle": "bob.bsky.social",
            "displayName": "Bob",
            "avatar": "https://cdn.example/bob.jpg"
          },
          "reason": "like",
          "reasonSubject": "at://did:plc:me/app.bsky.feed.post/mine",
          "record": { "$type": "app.bsky.feed.like", "createdAt": "2026-06-04T12:00:00.000Z" },
          "isRead": false,
          "indexedAt": "2026-06-04T12:00:01.000Z"
        },
        {
          "uri": "at://did:plc:carol/app.bsky.feed.post/bbb",
          "cid": "cidreply",
          "author": { "did": "did:plc:carol", "handle": "carol.bsky.social" },
          "reason": "reply",
          "reasonSubject": "at://did:plc:me/app.bsky.feed.post/mine",
          "record": { "$type": "app.bsky.feed.post", "text": "nice work!", "createdAt": "2026-06-04T11:00:00.000Z" },
          "isRead": true,
          "indexedAt": "2026-06-04T11:00:01.000Z"
        },
        {
          "uri": "at://did:plc:dave/app.bsky.graph.follow/ccc",
          "cid": "cidfollow",
          "author": { "did": "did:plc:dave", "handle": "dave.bsky.social", "displayName": "Dave" },
          "reason": "follow",
          "record": { "$type": "app.bsky.graph.follow", "createdAt": "2026-06-04T10:00:00.000Z" },
          "isRead": false,
          "indexedAt": "2026-06-04T10:00:01.000Z"
        },
        {
          "uri": "at://did:plc:eve/app.bsky.feed.post/ddd",
          "cid": "cidother",
          "author": { "did": "did:plc:eve", "handle": "eve.bsky.social" },
          "reason": "starterpack-joined",
          "record": { "$type": "app.bsky.feed.post", "createdAt": "2026-06-04T09:00:00.000Z" },
          "isRead": false,
          "indexedAt": "2026-06-04T09:00:01.000Z"
        }
      ]
    }
    """;

    private static ListNotificationsResponse DecodeFixture() =>
        ListNotificationsResponse.FromJson(JsonElement.Parse(Fixture));

    [Fact]
    public void DecodesCursorAndAllItems()
    {
        var response = DecodeFixture();

        Assert.Equal("next-page", response.Cursor);
        Assert.Equal(4, response.Notifications.Count);
    }

    [Fact]
    public void DecodesLikeNotification()
    {
        var item = DecodeFixture().Notifications[0];

        Assert.Equal(new NotificationReason.Like(), item.Reason);
        Assert.Equal("bob.bsky.social", item.Author.Handle);
        Assert.Equal("https://cdn.example/bob.jpg", item.Author.Avatar);
        Assert.Equal("at://did:plc:me/app.bsky.feed.post/mine", item.ReasonSubject);
        Assert.Null(item.RecordText);
        Assert.False(item.IsRead);
    }

    [Fact]
    public void DecodesReplyNotificationText()
    {
        var item = DecodeFixture().Notifications[1];

        Assert.Equal(new NotificationReason.Reply(), item.Reason);
        Assert.Equal("nice work!", item.RecordText);
        Assert.True(item.IsRead);
    }

    [Fact]
    public void FollowHasNoReasonSubject()
    {
        var item = DecodeFixture().Notifications[2];

        Assert.Equal(new NotificationReason.Follow(), item.Reason);
        Assert.Null(item.ReasonSubject);
    }

    [Fact]
    public void UnknownReasonDecodesToOther()
    {
        var item = DecodeFixture().Notifications[3];

        Assert.Equal(new NotificationReason.Other("starterpack-joined"), item.Reason);
    }
}
