using System.Text.Json;

namespace YoruMimizuku.Core.Tests;

public class NotificationSubjectsTests
{
    /// Answers getPosts from a fixed set of posts and records each request's URIs.
    private sealed class FakePosts(params PostView[] posts) : IPostsService
    {
        public List<IReadOnlyList<string>> Requests { get; } = [];

        public Task<GetPostsResponse> GetPostsAsync(IReadOnlyList<string> uris, CancellationToken cancellationToken)
        {
            Requests.Add(uris);
            return Task.FromResult(new GetPostsResponse(posts.Where(p => uris.Contains(p.Uri)).ToList()));
        }
    }

    private static PostView Subject(string uri, string text, params string[] thumbs) =>
        new(
            uri,
            "cid",
            new ProfileViewBasic("did:plc:me", "me.bsky.social", null, null, false),
            new PostRecord(text, "2026-06-04T12:00:00.000Z", []),
            null,
            null,
            null,
            "2026-06-04T12:00:01.000Z",
            thumbs.Length == 0
                ? null
                : new PostEmbed(thumbs.Select(t => new EmbedImage(t, t + "-full", "", null)).ToList(), null, null, null),
            null,
            []);

    private static BskyNotification Notification(string id, NotificationReason reason, string? subjectUri) =>
        new(
            $"at://did:plc:a/record/{id}",
            $"cid{id}",
            new ProfileViewBasic("did:plc:a", "a.example", null, null, false),
            reason,
            subjectUri,
            null,
            false,
            "2026-06-04T12:00:00.000Z");

    [Fact]
    public async Task FetchesEachLikedOrRepostedPostOnceAndAttachesItsTextAndFirstImage()
    {
        var groups = NotificationGroup.Group([
            Notification("1", new NotificationReason.Like(), "at://s/1"),
            Notification("2", new NotificationReason.Like(), "at://s/1"),
            Notification("3", new NotificationReason.Repost(), "at://s/1"),
            Notification("4", new NotificationReason.Like(), "at://s/2"),
            Notification("5", new NotificationReason.Repost(), "at://s/gone"),
            Notification("6", new NotificationReason.Reply(), "at://s/3"),
            Notification("7", new NotificationReason.Follow(), null),
        ]);
        var posts = new FakePosts(
            Subject("at://s/1", "liked post", "https://cdn.example/a.jpg", "https://cdn.example/b.jpg"),
            Subject("at://s/2", "text only"),
            Subject("at://s/3", "replied-to post"));

        var hydrated = await NotificationSubjects.HydrateAsync(groups, posts);

        Assert.Equal([["at://s/1", "at://s/2", "at://s/gone"]], posts.Requests);
        Assert.Equal(
            [
                ("liked post", new Uri("https://cdn.example/a.jpg")),
                ("liked post", new Uri("https://cdn.example/a.jpg")),
                ("text only", null),
                (null, null),
                (null, null),
                (null, null),
            ],
            hydrated.Select(g => (g.SubjectText, g.SubjectImageUrl)));
        Assert.Equal(groups.Select(g => g.Id), hydrated.Select(g => g.Id));
    }

    [Fact]
    public async Task BatchesAtMostTwentyFiveUrisPerRequest()
    {
        var uris = Enumerable.Range(0, 30).Select(i => $"at://s/{i}").ToList();
        var groups = NotificationGroup.Group(uris.Select((uri, i) => Notification($"{i}", new NotificationReason.Like(), uri)).ToList());
        var posts = new FakePosts(uris.Select(uri => Subject(uri, $"text of {uri}")).ToArray());

        var hydrated = await NotificationSubjects.HydrateAsync(groups, posts);

        Assert.Equal([uris[..25], uris[25..]], posts.Requests);
        Assert.Equal(uris.Select(uri => $"text of {uri}"), hydrated.Select(g => g.SubjectText));
    }

    [Fact]
    public async Task MakesNoRequestWithoutLikeOrRepostSubjects()
    {
        var groups = NotificationGroup.Group([
            Notification("1", new NotificationReason.Reply(), "at://s/1"),
            Notification("2", new NotificationReason.Follow(), null),
        ]);
        var posts = new FakePosts();

        var hydrated = await NotificationSubjects.HydrateAsync(groups, posts);

        Assert.Empty(posts.Requests);
        Assert.Equal(groups, hydrated);
    }

    [Fact]
    public void DecodesGetPostsResponse()
    {
        var body = """
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

        var response = GetPostsResponse.FromJson(JsonElement.Parse(body));

        Assert.Equal("hello world", Assert.Single(response.Posts).Record.Text);
    }
}
