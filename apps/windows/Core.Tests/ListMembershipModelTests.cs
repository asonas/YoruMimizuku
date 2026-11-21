namespace YoruMimizuku.Core.Tests;

/// Port of core/Tests/YoruMimizukuKitTests/ListMembershipModelTests.swift.
public class ListMembershipModelTests
{
    private const string Close = "at://did:plc:me/app.bsky.graph.list/close";
    private const string Swift = "at://did:plc:me/app.bsky.graph.list/swift";
    private const string Alice = "did:plc:alice";
    private const string Bob = "did:plc:bob";

    private sealed class Failure : Exception;

    /// An in-memory stand-in for the server: which actors are on which list.
    /// <see cref="HoldNextRead"/> / <see cref="HoldNextAdd"/> park the next such call
    /// (after it has taken its snapshot) until <see cref="Release"/>, so a test controls
    /// the order. Continuations run inline, so everything stays on the test's thread.
    private sealed class FakeServer(params (string Uri, string Name)[] lists) : IListMembershipEditor
    {
        private readonly List<(string Uri, string Name)> _lists = [.. lists];
        private readonly Dictionary<string, (string Actor, string List)> _items = [];
        private Dictionary<string, (string Actor, string List)>? _frozenItems;
        private readonly HashSet<string> _failingActors = [];
        private int _nextId;
        private bool _holdRead;
        private bool _holdAdd;
        private TaskCompletionSource? _gate;
        private TaskCompletionSource _parked = new();

        public List<string> Writes { get; } = [];
        public int Reads { get; private set; }

        public string PutOnList(string actor, string list)
        {
            var uri = $"at://did:plc:me/app.bsky.graph.listitem/{++_nextId}";
            _items[uri] = (actor, list);
            return uri;
        }

        public void HoldNextRead() => _holdRead = true;
        public void HoldNextAdd() => _holdAdd = true;
        public void FailReads(string actor) => _failingActors.Add(actor);
        /// Reads stop seeing new list items, like an appview that has not indexed a fresh record yet.
        public void FreezeReads() => _frozenItems = new(_items);
        public void AddList((string Uri, string Name) list) => _lists.Add(list);

        /// Completes once a held call is waiting.
        public Task Parked => _gate is not null ? Task.CompletedTask : _parked.Task;

        public void Release()
        {
            var gate = _gate;
            _gate = null;
            gate?.SetResult();
        }

        private async Task ParkAsync()
        {
            var gate = _gate = new TaskCompletionSource();
            var parked = _parked;
            _parked = new TaskCompletionSource();
            parked.SetResult();
            await gate.Task;
        }

        public async Task<IReadOnlyList<CuratedListMembership>> ListsWithMembershipAsync(
            string actorDid, CancellationToken cancellationToken = default)
        {
            Reads++;
            if (_failingActors.Contains(actorDid)) throw new Failure();
            var visible = _frozenItems ?? _items;
            var snapshot = _lists.Select(list => new CuratedListMembership(
                list.Uri, list.Name,
                visible.Where(i => i.Value.Actor == actorDid && i.Value.List == list.Uri).Select(i => i.Key).FirstOrDefault()))
                .ToList();
            if (_holdRead)
            {
                _holdRead = false;
                await ParkAsync();
            }
            return snapshot;
        }

        public async Task<string> AddAsync(string actorDid, string listUri, CancellationToken cancellationToken = default)
        {
            if (_holdAdd)
            {
                _holdAdd = false;
                await ParkAsync();
            }
            Writes.Add($"add {actorDid} {listUri}");
            return PutOnList(actorDid, listUri);
        }

        public Task RemoveAsync(string itemUri, CancellationToken cancellationToken = default)
        {
            Writes.Add($"remove {itemUri}");
            _items.Remove(itemUri);
            return Task.CompletedTask;
        }
    }

    private static readonly (string, string) CloseList = (Close, "近しい人");
    private static readonly (string, string) SwiftList = (Swift, "Swift");

    [Fact]
    public async Task RefreshListsTheOwnListsAndWhetherTheActorIsOnEach()
    {
        var server = new FakeServer(CloseList, SwiftList);
        server.PutOnList(Alice, Close);
        var model = new ListMembershipModel(server);

        await model.RefreshAsync(Alice);

        Assert.Equal(["近しい人", "Swift"], model.Lists.Select(l => l.Name));
        Assert.True(model.IsMember(Alice, Close));
        Assert.False(model.IsMember(Alice, Swift));
        Assert.Null(model.IsMember(Bob, Close));
    }

    private sealed class FailingEditor : IListMembershipEditor
    {
        public Task<IReadOnlyList<CuratedListMembership>> ListsWithMembershipAsync(string actorDid, CancellationToken cancellationToken = default) =>
            throw new Failure();
        public Task<string> AddAsync(string actorDid, string listUri, CancellationToken cancellationToken = default) => throw new Failure();
        public Task RemoveAsync(string itemUri, CancellationToken cancellationToken = default) => throw new Failure();
    }

    /// The menu must tell "you have no lists" apart from "the lists did not load".
    [Fact]
    public async Task ListsStateTellsNoListsApartFromAFailedLoad()
    {
        var empty = new ListMembershipModel(new FakeServer());
        var failing = new ListMembershipModel(new FailingEditor());
        Assert.Equal(ListsState.NotLoaded, empty.ListsState);

        await empty.RefreshAsync(Alice);
        await failing.RefreshAsync(Alice);

        Assert.Equal(ListsState.Loaded, empty.ListsState);
        Assert.Equal(ListsState.Failed, failing.ListsState);
    }
    [Fact]
    public async Task AddingPutsTheActorOnTheList()
    {
        var server = new FakeServer(CloseList);
        var model = new ListMembershipModel(server);

        var wrote = await model.SetMembershipAsync(Alice, Close, true);

        Assert.True(wrote);
        Assert.True(model.IsMember(Alice, Close));
        Assert.Equal([$"add {Alice} {Close}"], server.Writes);
    }
    /// The cache can be stale (another client added the actor), and the PDS accepts a
    /// second identical list item, so a write re-reads first.
    [Fact]
    public async Task AddingAnActorAlreadyOnTheListWritesNothing()
    {
        var server = new FakeServer(CloseList);
        var model = new ListMembershipModel(server);
        await model.RefreshAsync(Alice);
        server.PutOnList(Alice, Close);

        var wrote = await model.SetMembershipAsync(Alice, Close, true);

        Assert.False(wrote);
        Assert.Empty(server.Writes);
        Assert.True(model.IsMember(Alice, Close));
    }
    [Fact]
    public async Task RemovingTakesTheActorOffTheList()
    {
        var server = new FakeServer(CloseList);
        var item = server.PutOnList(Alice, Close);
        var model = new ListMembershipModel(server);

        await model.SetMembershipAsync(Alice, Close, false);

        Assert.False(model.IsMember(Alice, Close));
        Assert.Equal([$"remove {item}"], server.Writes);
    }
    /// A list the server did not return (deleted, or past the first page) cannot be
    /// checked, so nothing is written.
    [Fact]
    public async Task ChangingAListTheServerDidNotReturnFails()
    {
        var server = new FakeServer(CloseList);
        var model = new ListMembershipModel(server);

        await Assert.ThrowsAsync<ListNotFoundException>(
            () => model.SetMembershipAsync(Alice, "at://did:plc:me/app.bsky.graph.list/gone", true));

        Assert.Empty(server.Writes);
    }
    /// Two quick drops of the same person must not create two list items: the second
    /// change waits for the first and then sees the person on the list.
    [Fact]
    public async Task TwoOverlappingAddsWriteOnce()
    {
        var server = new FakeServer(CloseList);
        var model = new ListMembershipModel(server);
        server.HoldNextAdd();

        var first = model.SetMembershipAsync(Alice, Close, true);
        await server.Parked;
        var second = model.SetMembershipAsync(Alice, Close, true);
        server.Release();
        await first;
        var secondWrote = await second;

        Assert.False(secondWrote);
        Assert.Equal([$"add {Alice} {Close}"], server.Writes);
    }
    /// A prefetch that started before a change and answers after it must not clear the
    /// check the change just set.
    [Fact]
    public async Task AnOlderReadDoesNotUndoANewerChange()
    {
        var server = new FakeServer(CloseList);
        var model = new ListMembershipModel(server);
        server.HoldNextRead();

        var prefetch = model.RefreshAsync(Alice);
        await server.Parked;
        await model.SetMembershipAsync(Alice, Close, true);
        server.Release();
        await prefetch;

        Assert.True(model.IsMember(Alice, Close));
    }
    /// The appview indexes a new list item after a delay; a second drop right after the
    /// first must not create another item.
    [Fact]
    public async Task ASecondAddRightAfterTheFirstWritesNothingWhileTheServerLags()
    {
        var server = new FakeServer(CloseList);
        var model = new ListMembershipModel(server);
        server.FreezeReads();

        await model.SetMembershipAsync(Alice, Close, true);
        var second = await model.SetMembershipAsync(Alice, Close, true);

        Assert.False(second);
        Assert.Equal([$"add {Alice} {Close}"], server.Writes);
        Assert.True(model.IsMember(Alice, Close));
    }
    /// After this window removes someone, another device may add them back with a new
    /// list item; that new item is not the removal still being indexed.
    [Fact]
    public async Task AReAddFromAnotherDeviceIsNotHiddenByARecentRemoval()
    {
        var server = new FakeServer(CloseList);
        server.PutOnList(Alice, Close);
        var model = new ListMembershipModel(server);
        await model.SetMembershipAsync(Alice, Close, false);
        server.PutOnList(Alice, Close);

        var wrote = await model.SetMembershipAsync(Alice, Close, true);

        Assert.False(wrote);
        Assert.True(model.IsMember(Alice, Close));
    }

    /// A change's own read must land even when a prefetch overlaps it, so lists other
    /// than the changed one keep their checks.
    [Fact]
    public async Task AChangeKeepsOtherListsCheckedWhenAPrefetchOverlaps()
    {
        var server = new FakeServer(CloseList, SwiftList);
        server.PutOnList(Alice, Swift);
        var model = new ListMembershipModel(server);
        server.HoldNextRead();

        var change = model.SetMembershipAsync(Alice, Close, true);
        await server.Parked;
        await model.RefreshAsync(Alice);
        server.Release();
        await change;

        Assert.True(model.IsMember(Alice, Close));
        Assert.True(model.IsMember(Alice, Swift));
    }

    /// A list that first appears while reading someone else was never checked for this
    /// author, so it is unknown rather than "not on it".
    [Fact]
    public async Task AListThatAppearedLaterIsUnknownForAnAuthorReadBefore()
    {
        var server = new FakeServer(CloseList);
        var model = new ListMembershipModel(server);
        await model.RefreshAsync(Alice);
        server.AddList(SwiftList);

        await model.RefreshAsync(Bob);

        Assert.Equal(["近しい人", "Swift"], model.Lists.Select(l => l.Name));
        Assert.False(model.IsMember(Alice, Close));
        Assert.Null(model.IsMember(Alice, Swift));
    }
    /// A later read failing must not throw away an earlier read that succeeded.
    [Fact]
    public async Task AnEarlierSuccessfulReadStillFillsTheListsWhenALaterOneFails()
    {
        var server = new FakeServer(CloseList);
        var model = new ListMembershipModel(server);
        server.FailReads(Bob);
        server.HoldNextRead();

        var alice = model.RefreshAsync(Alice);
        await server.Parked;
        await model.RefreshAsync(Bob);
        server.Release();
        await alice;

        Assert.Equal(ListsState.Loaded, model.ListsState);
        Assert.Equal(["近しい人"], model.Lists.Select(l => l.Name));
        Assert.False(model.IsMember(Alice, Close));
    }

    /// The lists take a read's answer only if no later-started read has filled them
    /// (the Swift model's readsStarted / listsFilledBy), so a slow older read never
    /// replaces newer lists.
    [Fact]
    public async Task AnOlderReadAnsweringLateDoesNotReplaceNewerLists()
    {
        var server = new FakeServer(CloseList);
        var model = new ListMembershipModel(server);
        server.HoldNextRead();

        var alice = model.RefreshAsync(Alice);
        await server.Parked;
        server.AddList(SwiftList);
        await model.RefreshAsync(Bob);
        server.Release();
        await alice;

        Assert.Equal(["近しい人", "Swift"], model.Lists.Select(l => l.Name));
    }
    private sealed class ManualClock : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = DateTimeOffset.UnixEpoch;
        public override DateTimeOffset GetUtcNow() => Now;
    }

    [Fact]
    public async Task RefreshIfStaleSkipsAFreshActor()
    {
        var server = new FakeServer(CloseList);
        var clock = new ManualClock();
        var model = new ListMembershipModel(server, clock);

        await model.RefreshIfStaleAsync(Alice);
        clock.Now = DateTimeOffset.UnixEpoch.AddSeconds(30);
        await model.RefreshIfStaleAsync(Alice);
        var readsWhileFresh = server.Reads;
        clock.Now = DateTimeOffset.UnixEpoch.AddSeconds(61);
        await model.RefreshIfStaleAsync(Alice);

        Assert.Equal(1, readsWhileFresh);
        Assert.Equal(2, server.Reads);
    }
    private sealed class FailOnceEditor : IListMembershipEditor
    {
        public int Reads { get; private set; }

        public Task<IReadOnlyList<CuratedListMembership>> ListsWithMembershipAsync(string actorDid, CancellationToken cancellationToken = default) =>
            ++Reads == 1 ? throw new Failure() : Task.FromResult<IReadOnlyList<CuratedListMembership>>([]);
        public Task<string> AddAsync(string actorDid, string listUri, CancellationToken cancellationToken = default) => Task.FromResult("");
        public Task RemoveAsync(string itemUri, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }

    [Fact]
    public async Task AFailedPrefetchIsRetriedAtTheNextChance()
    {
        var editor = new FailOnceEditor();
        var clock = new ManualClock();
        var model = new ListMembershipModel(editor, clock);

        await model.RefreshIfStaleAsync(Alice);
        clock.Now = DateTimeOffset.UnixEpoch.AddSeconds(1);
        await model.RefreshIfStaleAsync(Alice);

        Assert.Equal(2, editor.Reads);
    }

    /// An open menu redraws from the cache when this fires (the Swift model is an
    /// ObservableObject).
    [Fact]
    public async Task ChangedFiresWhenAReadOrAChangeUpdatesTheCache()
    {
        var server = new FakeServer(CloseList);
        var model = new ListMembershipModel(server);
        var changes = 0;
        model.Changed += () => changes++;

        await model.RefreshAsync(Alice);
        var afterRead = changes;
        await model.SetMembershipAsync(Alice, Close, true);

        Assert.True(afterRead > 0);
        Assert.True(changes > afterRead);
    }
}
