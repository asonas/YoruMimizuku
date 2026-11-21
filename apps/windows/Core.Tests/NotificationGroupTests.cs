using System.Text.Json;

namespace YoruMimizuku.Core.Tests;

public class NotificationGroupTests
{
    private static BskyNotification Notification(
        string id,
        NotificationReason reason,
        string handle,
        string? subjectUri,
        string? text = null,
        int indexedAt = 0,
        bool isRead = false,
        string? displayName = null,
        string? avatar = null) =>
        new(
            $"at://did:plc:{handle}/record/{id}",
            $"cid{id}",
            new ProfileViewBasic($"did:plc:{handle}", handle, displayName, avatar, false),
            reason,
            subjectUri,
            text,
            isRead,
            DateTimeOffset.FromUnixTimeSeconds(indexedAt).ToString("O"));

    // -- One notification's row (NotificationDisplayMappingTests) --

    [Fact]
    public void MapsAuthorReasonAndText()
    {
        var group = Assert.Single(NotificationGroup.Group([
            Notification("1", new NotificationReason.Reply(), "bob.bsky.social", "at://did:plc:me/app.bsky.feed.post/mine",
                text: "nice work!", displayName: "Bob", avatar: "https://cdn.example/bob.jpg"),
        ]));

        Assert.Equal(new NotificationReason.Reply(), group.Reason);
        Assert.Equal(new NotificationActor("Bob", "bob.bsky.social", new Uri("https://cdn.example/bob.jpg")), Assert.Single(group.Actors));
        Assert.Equal("nice work!", group.Text);
        Assert.False(group.IsRead);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public void FallsBackToHandleWhenNoDisplayName(string? displayName)
    {
        var group = Assert.Single(NotificationGroup.Group([
            Notification("1", new NotificationReason.Follow(), "bob.bsky.social", null, displayName: displayName),
        ]));

        Assert.Equal("bob.bsky.social", group.Actors[0].DisplayName);
        Assert.Null(group.Text);
    }

    [Fact]
    public void ParsesIndexedAtTimestamp()
    {
        var notification = Notification("1", new NotificationReason.Like(), "bob", "at://post/1") with
        {
            IndexedAt = "2026-06-04T12:00:00.000Z",
        };

        var group = Assert.Single(NotificationGroup.Group([notification]));

        Assert.Equal(new DateTimeOffset(2026, 6, 4, 12, 0, 0, TimeSpan.Zero), group.LatestCreatedAt);
    }

    [Fact]
    public void SingleRowIdentityCombinesUriAndCid()
    {
        // The same actor liking and replying must yield distinct rows.
        var group = Assert.Single(NotificationGroup.Group([
            Notification("1", new NotificationReason.Reply(), "bob", "at://post/1"),
        ]));

        Assert.Equal("single|at://did:plc:bob/record/1|cid1", group.Id);
    }

    [Fact]
    public void MapsReasonSubjectToSubjectUri()
    {
        var group = Assert.Single(NotificationGroup.Group([
            Notification("1", new NotificationReason.Like(), "bob", "at://did:plc:me/app.bsky.feed.post/mine"),
        ]));

        Assert.Equal("at://did:plc:me/app.bsky.feed.post/mine", group.SubjectUri);
    }

    // -- Grouping (NotificationGroupTests) --

    [Fact]
    public void GroupsLikesOnSameSubjectIntoOneGroupWithMultipleActors()
    {
        var group = Assert.Single(NotificationGroup.Group([
            Notification("1", new NotificationReason.Like(), "a", "at://post/1"),
            Notification("2", new NotificationReason.Like(), "b", "at://post/1"),
        ]));

        Assert.Equal(new NotificationReason.Like(), group.Reason);
        Assert.Equal(["a", "b"], group.Actors.Select(a => a.Handle));
        Assert.Equal("at://post/1", group.SubjectUri);
        Assert.Equal("like|at://post/1", group.Id);
    }

    [Fact]
    public void LikeAndRepostOnSameSubjectAreSeparateGroups()
    {
        var groups = NotificationGroup.Group([
            Notification("1", new NotificationReason.Like(), "a", "at://post/1"),
            Notification("2", new NotificationReason.Repost(), "a", "at://post/1"),
        ]);

        Assert.Equal(2, groups.Count);
    }

    [Fact]
    public void RepliesAreNotGrouped()
    {
        var groups = NotificationGroup.Group([
            Notification("1", new NotificationReason.Reply(), "a", "at://post/1", text: "hi"),
            Notification("2", new NotificationReason.Reply(), "b", "at://post/1", text: "yo"),
        ]);

        Assert.Equal(2, groups.Count);
        Assert.Single(groups[0].Actors);
    }

    [Fact]
    public void PreservesFirstOccurrenceOrder()
    {
        var groups = NotificationGroup.Group([
            Notification("1", new NotificationReason.Like(), "a", "at://post/1"),
            Notification("2", new NotificationReason.Follow(), "b", null),
            Notification("3", new NotificationReason.Like(), "c", "at://post/1"),
        ]);

        Assert.Equal(2, groups.Count);
        Assert.Equal(new NotificationReason.Like(), groups[0].Reason);
        Assert.Equal(["a", "c"], groups[0].Actors.Select(a => a.Handle));
        Assert.Equal(new NotificationReason.Follow(), groups[1].Reason);
    }

    [Fact]
    public void GroupIsReadOnlyWhenAllItemsRead()
    {
        var group = Assert.Single(NotificationGroup.Group([
            Notification("1", new NotificationReason.Like(), "a", "at://post/1", isRead: true),
            Notification("2", new NotificationReason.Like(), "b", "at://post/1", isRead: false),
        ]));

        Assert.False(group.IsRead);
    }

    [Fact]
    public void LatestCreatedAtIsMaxOfGroup()
    {
        var group = Assert.Single(NotificationGroup.Group([
            Notification("1", new NotificationReason.Like(), "a", "at://post/1", indexedAt: 200),
            Notification("2", new NotificationReason.Like(), "b", "at://post/1", indexedAt: 100),
        ]));

        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(200), group.LatestCreatedAt);
    }

    [Fact]
    public void ActionSummarySingleLikeReadsBlueskyStyle()
    {
        var group = Assert.Single(NotificationGroup.Group([
            Notification("1", new NotificationReason.Like(), "joker1007", "at://post/1"),
        ]));

        Assert.Equal("joker1007があなたの投稿をいいねしました", group.ActionSummary);
    }

    [Fact]
    public void ActionSummaryAggregatedLikeMentionsOthersCount()
    {
        var group = Assert.Single(NotificationGroup.Group([
            Notification("1", new NotificationReason.Like(), "joker1007", "at://post/1"),
            Notification("2", new NotificationReason.Like(), "kiryuanzu", "at://post/1"),
            Notification("3", new NotificationReason.Like(), "kakutani", "at://post/1"),
        ]));

        Assert.Equal("joker1007および他2人があなたの投稿をいいねしました", group.ActionSummary);
    }

    [Fact]
    public void ActionSummaryFollowHasNoSubjectPhrase()
    {
        var group = Assert.Single(NotificationGroup.Group([
            Notification("1", new NotificationReason.Follow(), "kokko", null),
        ]));

        Assert.Equal("kokkoがあなたをフォローしました", group.ActionSummary);
    }

    [Fact]
    public void ActionSummaryRepostUsesRepostVerb()
    {
        var group = Assert.Single(NotificationGroup.Group([
            Notification("1", new NotificationReason.Repost(), "alice", "at://post/1"),
            Notification("2", new NotificationReason.Repost(), "bob", "at://post/1"),
        ]));

        Assert.Equal("aliceおよび他1人があなたの投稿をリポストしました", group.ActionSummary);
    }

    // -- Decode, map and group a live-shaped page (NotificationPipelineRegressionTests) --

    /// A page shaped like production data: a like, a reply whose record carries a
    /// reply ref, an image embed and rich profile extras, and a reason newer than the
    /// known set. Guards against the reply being dropped between decoding and grouping.
    private const string LivePage = """
    {
      "cursor": "2026-06-10T08:55:37.066Z",
      "notifications": [
        {
          "uri": "at://did:plc:liker/app.bsky.feed.like/3mnwxyz",
          "cid": "bafylike",
          "author": {
            "did": "did:plc:liker",
            "handle": "liker.bsky.social",
            "displayName": "Liker",
            "avatar": "https://cdn.bsky.app/img/avatar/plain/did:plc:liker/bafkavatar",
            "associated": { "chat": { "allowIncoming": "following" } },
            "labels": [],
            "createdAt": "2023-06-22T14:05:03.241Z"
          },
          "reason": "like",
          "reasonSubject": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m",
          "record": {
            "$type": "app.bsky.feed.like",
            "createdAt": "2026-06-10T09:00:00.000Z",
            "subject": { "cid": "bafyparent", "uri": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m" }
          },
          "isRead": false,
          "indexedAt": "2026-06-10T09:00:01.000Z"
        },
        {
          "uri": "at://did:plc:replier/app.bsky.feed.post/3mnwdnozac22s",
          "cid": "bafyreply",
          "author": {
            "did": "did:plc:replier",
            "handle": "replier.s01.ninja",
            "displayName": "Replier / G4",
            "avatar": "https://cdn.bsky.app/img/avatar/plain/did:plc:replier/bafkavatar2",
            "associated": {
              "chat": { "allowIncoming": "following" },
              "activitySubscription": { "allowSubscriptions": "followers" }
            },
            "labels": [],
            "createdAt": "2023-06-22T14:05:03.241Z"
          },
          "reason": "reply",
          "reasonSubject": "at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m",
          "record": {
            "$type": "app.bsky.feed.post",
            "createdAt": "2026-06-10T08:55:21.213Z",
            "embed": {
              "$type": "app.bsky.embed.images",
              "images": [
                {
                  "alt": "",
                  "aspectRatio": { "height": 1206, "width": 1518 },
                  "image": {
                    "$type": "blob",
                    "ref": { "$link": "bafkreimage" },
                    "mimeType": "image/jpeg",
                    "size": 1807448
                  }
                }
              ]
            },
            "langs": ["ja"],
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
          "record": {
            "$type": "app.bsky.feed.post",
            "createdAt": "2026-06-10T08:00:00.000Z",
            "text": "subscribed activity"
          },
          "isRead": false,
          "indexedAt": "2026-06-10T08:00:01.000Z"
        }
      ]
    }
    """;

    [Fact]
    public void ReplySurvivesDecodeMapAndGrouping()
    {
        var response = ListNotificationsResponse.FromJson(JsonElement.Parse(LivePage));
        Assert.Equal(3, response.Notifications.Count);

        var groups = NotificationGroup.Group(response.Notifications);

        var reply = Assert.Single(groups, g => g.Reason is NotificationReason.Reply);
        Assert.Equal("replier.s01.ninja", reply.Actors[0].Handle);
        Assert.Equal(":eyes:", reply.Text);
        Assert.Equal("at://did:plc:me/app.bsky.feed.post/3mnwc34o2ai2m", reply.SubjectUri);
        // Page order (newest first) is kept: like, reply, then the unknown reason.
        Assert.Equal(
            [new NotificationReason.Like(), new NotificationReason.Reply(), new NotificationReason.Other("subscribed-post")],
            groups.Select(g => g.Reason));
    }
}
