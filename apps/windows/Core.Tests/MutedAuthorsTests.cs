namespace YoruMimizuku.Core.Tests;

// Ported from the Muting cases of core/Tests/YoruMimizukuKitTests/TimelineViewModelTests.swift.
// Windows rebuilds a timeline each time it is shown, so the window keeps who was muted
// and every timeline filters its pages through it.
public class MutedAuthorsTests
{
    [Fact]
    public void MutingAnAuthorHidesTheirPostsOnly()
    {
        var muted = new MutedAuthors();

        muted.Mute("did:plc:bob");

        string[] page =
        [
            "at://did:plc:bob/app.bsky.feed.post/1",
            "at://did:plc:alice/app.bsky.feed.post/2",
            "at://did:plc:bob/app.bsky.feed.post/3",
        ];
        Assert.Equal(["at://did:plc:alice/app.bsky.feed.post/2"], page.Where(uri => !muted.Hides(uri)));
    }

    /// The timelines on screen drop the author's posts when told; muting the same
    /// author again tells them nothing new.
    [Fact]
    public void AuthorMutedIsRaisedOncePerAuthor()
    {
        var muted = new MutedAuthors();
        var raised = new List<string>();
        muted.AuthorMuted += raised.Add;

        muted.Mute("did:plc:bob");
        muted.Mute("did:plc:bob");

        Assert.Equal(["did:plc:bob"], raised);
    }

    /// Mutes belong to the window's account, so signing in as another one forgets them.
    [Fact]
    public void ClearForgetsEveryMute()
    {
        var muted = new MutedAuthors();
        muted.Mute("did:plc:bob");

        muted.Clear();

        Assert.False(muted.Hides("at://did:plc:bob/app.bsky.feed.post/1"));
    }
}
