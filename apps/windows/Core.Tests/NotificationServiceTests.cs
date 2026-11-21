using System.Net;

namespace YoruMimizuku.Core.Tests;

public class NotificationServiceTests
{
    private const string NotificationsBody = """
        {
          "cursor": "next",
          "notifications": [
            {
              "uri": "at://did:plc:bob/app.bsky.feed.like/aaa",
              "cid": "cidlike",
              "author": { "did": "did:plc:bob", "handle": "bob.bsky.social", "displayName": "Bob" },
              "reason": "like",
              "reasonSubject": "at://did:plc:me/app.bsky.feed.post/mine",
              "record": { "$type": "app.bsky.feed.like", "createdAt": "2026-06-04T12:00:00.000Z" },
              "isRead": false,
              "indexedAt": "2026-06-04T12:00:01.000Z"
            },
            {
              "uri": "at://did:plc:carol/app.bsky.feed.like/bbb",
              "cid": "cidlike2",
              "author": { "did": "did:plc:carol", "handle": "carol.bsky.social" },
              "reason": "like",
              "reasonSubject": "at://did:plc:me/app.bsky.feed.post/mine",
              "record": { "$type": "app.bsky.feed.like", "createdAt": "2026-06-04T11:00:00.000Z" },
              "isRead": false,
              "indexedAt": "2026-06-04T11:00:01.000Z"
            }
          ]
        }
        """;

    private const string PostsBody = """
        {
          "posts": [
            {
              "uri": "at://did:plc:me/app.bsky.feed.post/mine",
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

    [Fact]
    public async Task ListNotificationsAsksForEveryNotificationAndDecodes()
    {
        var http = new StubHttp(NotificationsBody);

        var page = await new NotificationService(http.Xrpc()).ListNotificationsAsync();

        Assert.Equal(new NotificationReason.Like(), page.Notifications[0].Reason);
        Assert.Equal("next", page.Cursor);
        Assert.Equal("/xrpc/app.bsky.notification.listNotifications", http.Last.Path);
        Assert.Equal("50", http.Last.Query["limit"]);
        // Without it the AppView applies the account's priority setting and drops
        // notifications, such as replies, from accounts the viewer does not follow.
        Assert.Equal("false", http.Last.Query["priority"]);
    }

    [Fact]
    public async Task ListNotificationsSendsTheCursorUnchanged()
    {
        var http = new StubHttp(NotificationsBody);

        await new NotificationService(http.Xrpc()).ListNotificationsAsync("1718000000000+bafy/x=y&z", limit: 20);

        Assert.Equal("1718000000000+bafy/x=y&z", http.Last.Query["cursor"]);
        Assert.Equal("20", http.Last.Query["limit"]);
    }

    [Fact]
    public async Task LoadGroupsGroupsTheFirstPageAndShowsWhatTheLikedPostSaid()
    {
        var http = new StubHttp(request => StubHttp.Json(
            request.Path == "/xrpc/app.bsky.feed.getPosts" ? PostsBody : NotificationsBody));

        var groups = await new NotificationService(http.Xrpc()).LoadGroupsAsync();

        var group = Assert.Single(groups);
        Assert.Equal(["Bob", "carol.bsky.social"], group.Actors.Select(a => a.DisplayName));
        Assert.Equal("hello world", group.SubjectText);
        Assert.Equal(new Uri("https://cdn.example/t.jpg"), group.SubjectImageUrl);
        Assert.Equal(["at://did:plc:me/app.bsky.feed.post/mine"], http.Single("app.bsky.feed.getPosts").Query.GetValues("uris")!);
    }

    // The snippets are an enhancement: losing them must not blank the notifications tab.
    [Fact]
    public async Task LoadGroupsKeepsTheRowsWithoutSnippetsWhenTheSubjectPostsFailToLoad()
    {
        var http = new StubHttp(request => request.Path == "/xrpc/app.bsky.feed.getPosts"
            ? StubHttp.Json("{}", HttpStatusCode.BadGateway)
            : StubHttp.Json(NotificationsBody));

        var groups = await new NotificationService(http.Xrpc()).LoadGroupsAsync();

        var group = Assert.Single(groups);
        Assert.Equal(2, group.Actors.Count);
        Assert.Null(group.SubjectText);
        Assert.Null(group.SubjectImageUrl);
    }
}
