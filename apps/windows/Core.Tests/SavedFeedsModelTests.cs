namespace YoruMimizuku.Core.Tests;

/// Ported from core/Tests/YoruMimizukuKitTests/SavedFeedsModelTests.swift.
public class SavedFeedsModelTests
{
    private static FeedGeneratorView Generator(string uri, string name) =>
        new(uri, new ProfileViewBasic("did:plc:c", "creator.example", null, null, false), name, $"about {name}", null);

    private static ListView List(string uri, string name) =>
        new(uri, name, null, null, new ProfileViewBasic("did:plc:me", "me.example", null, null, false),
            "app.bsky.graph.defs#curatelist");

    [Fact]
    public void PinnedSourcesFollowTheSavedOrderAndSkipWhatTheSidebarCannotShow()
    {
        SavedFeedItem[] items =
        [
            new("1", "timeline", "following", true),
            new("2", "feed", "at://f/b", true),
            new("3", "list", "at://l/close", true),
            new("4", "feed", "at://f/a", true),
            new("5", "feed", "at://f/unpinned", false),
            new("6", "feed", "at://f/deleted", true),
            new("7", "somethingNew", "x", true),
            new("8", "feed", "at://f/b", true),
        ];

        var sources = SavedFeedSource.Pinned(
            items,
            [Generator("at://f/a", "A"), Generator("at://f/b", "B")],
            [List("at://l/close", "近しい人")]);

        Assert.Equal(["at://f/b", "at://l/close", "at://f/a"], sources.Select(s => s.Id));
        Assert.Equal([SavedFeedKind.Feed, SavedFeedKind.List, SavedFeedKind.Feed], sources.Select(s => s.Kind));
        Assert.Equal(["B", "近しい人", "A"], sources.Select(s => s.Title));
        Assert.Equal("creator.example", sources[0].CreatorHandle);
        Assert.Equal("about B", sources[0].Description);
        Assert.Equal(["did:plc:c", "did:plc:me", "did:plc:c"], sources.Select(s => s.CreatorDid));
        Assert.Equal([false, true, false], sources.Select(s => s.IsCuratedList));
    }

    private static Func<Task<IReadOnlyList<string>>> Loads(params string[] ids) =>
        () => Task.FromResult<IReadOnlyList<string>>(ids);

    [Fact]
    public async Task AFailedReloadKeepsTheSourcesAlreadyShown()
    {
        var model = new SavedFeedsModel<string>();

        await model.LoadAsync(Loads("at://f/a"));
        await model.LoadAsync(() => Task.FromException<IReadOnlyList<string>>(new HttpRequestException("offline")));

        Assert.Equal(["at://f/a"], model.Sources);
    }

    [Fact]
    public async Task AnOlderLoadFinishingLastDoesNotOverwriteANewerOne()
    {
        var model = new SavedFeedsModel<string>();
        var gate = new TaskCompletionSource<IReadOnlyList<string>>();

        var older = model.LoadAsync(() => gate.Task);
        await model.LoadAsync(Loads("at://f/new"));
        gate.SetResult(["at://f/old"]);
        await older;

        Assert.Equal(["at://f/new"], model.Sources);
    }

    [Fact]
    public async Task ClearingDropsTheSourcesAndALoadStillInFlight()
    {
        var model = new SavedFeedsModel<string>();
        await model.LoadAsync(Loads("at://f/a"));
        var gate = new TaskCompletionSource<IReadOnlyList<string>>();

        var inFlight = model.LoadAsync(() => gate.Task);
        model.Clear();
        gate.SetResult(["at://f/previous-account"]);
        await inFlight;

        Assert.Empty(model.Sources);
    }
}
