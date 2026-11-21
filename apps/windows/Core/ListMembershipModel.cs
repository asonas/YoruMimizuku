namespace YoruMimizuku.Core;

/// <summary>One of the viewer's curated lists, as the "リストに追加" menu shows it.</summary>
public sealed record CuratedList(string Id, string Name);

public enum ListsState { NotLoaded, Loaded, Failed }

/// <summary>
/// The server did not return the list (deleted, or past the first page), so membership
/// cannot be checked before writing.
/// </summary>
public sealed class ListNotFoundException(string listUri) : Exception($"The list {listUri} was not returned.");

/// <summary>
/// The viewer's curated lists and a per-actor cache of who is on them, for the
/// "リストに追加" menu and for dropping a person on a list. A menu is built
/// synchronously, so it reads the cache. Changes run one at a time and re-read the
/// server first, because the PDS accepts duplicate list items; for the same reason a
/// change made here is trusted over a read for <see cref="RecentWriteWindow"/>, while
/// the appview has not indexed it yet. Share one instance per account so its windows
/// also take turns. Port of the Swift <c>ListMembershipModel</c>; used from one thread.
/// </summary>
public sealed class ListMembershipModel(IListMembershipEditor editor, TimeProvider? clock = null)
{
    private static readonly TimeSpan RecentWriteWindow = TimeSpan.FromSeconds(30);

    /// <summary>
    /// A change this model just made. A removal keeps the removed item's URI: a read
    /// still returning that item is the removal not yet indexed, while a different item
    /// is a re-add elsewhere.
    /// </summary>
    private sealed record RecentWrite(string? Added, string? Removed, DateTimeOffset At);

    /// <summary>actor DID → list URI → the change this model just made.</summary>
    private readonly Dictionary<string, Dictionary<string, RecentWrite>> _recentWrites = [];

    private DateTimeOffset Now => (clock ?? TimeProvider.System).GetUtcNow();

    /// <summary>actor DID → list URI → list item URI, for the lists read for that actor.</summary>
    private readonly Dictionary<string, Dictionary<string, string>> _items = [];

    /// <summary>actor DID → the lists whose membership was read for that actor.</summary>
    private readonly Dictionary<string, HashSet<string>> _checked = [];

    /// <summary>
    /// Bumped per actor by every read and change, so a read that answers after a newer
    /// read or change does not overwrite it.
    /// </summary>
    private readonly Dictionary<string, int> _generations = [];

    /// <summary>
    /// Reads are numbered when they start; <see cref="Lists"/> takes a read's answer only
    /// if no later-started read has already filled it, so a later failure never discards
    /// an earlier success.
    /// </summary>
    private int _readsStarted;
    private int _listsFilledBy;

    /// <summary>Changes run one at a time, so two quick drops cannot both see "not on it".</summary>
    private bool _isWriting;
    private readonly Queue<TaskCompletionSource> _writeWaiters = new();

    private readonly Dictionary<string, DateTimeOffset> _fetchedAt = [];
    private readonly HashSet<string> _inFlight = [];

    /// <summary>Raised when the lists, their state or a cached membership may have changed.</summary>
    public event Action? Changed;

    public IReadOnlyList<CuratedList> Lists { get; private set; } = [];

    /// <summary>
    /// Whether <see cref="Lists"/> reflects the server. A failed reload after a successful
    /// one stays <see cref="ListsState.Loaded"/>, since the lists shown are still the viewer's.
    /// </summary>
    public ListsState ListsState { get; private set; } = ListsState.NotLoaded;

    /// <summary>Whether <paramref name="actorDid"/> is on the list, or null when that has not been read.</summary>
    public bool? IsMember(string actorDid, string listUri)
    {
        if (!_checked.TryGetValue(actorDid, out var lists) || !lists.Contains(listUri)) return null;
        return _items.TryGetValue(actorDid, out var byList) && byList.ContainsKey(listUri);
    }

    /// <summary>
    /// Load the viewer's lists and <paramref name="actorDid"/>'s membership. A failure
    /// keeps what is already cached.
    /// </summary>
    public Task RefreshAsync(string actorDid) => TryFetchAsync(actorDid);

    /// <summary>
    /// <see cref="RefreshAsync"/>, unless <paramref name="actorDid"/> was read successfully
    /// within <paramref name="maxAge"/> (default 60 s) or a read is under way. Used for
    /// prefetching, which can fire for every post a menu opens on.
    /// </summary>
    public async Task RefreshIfStaleAsync(string actorDid, TimeSpan? maxAge = null)
    {
        var now = Now;
        if (_fetchedAt.TryGetValue(actorDid, out var last) && now - last < (maxAge ?? TimeSpan.FromSeconds(60))) return;
        if (!_inFlight.Add(actorDid)) return;
        try
        {
            if (await TryFetchAsync(actorDid)) _fetchedAt[actorDid] = now;
        }
        finally
        {
            _inFlight.Remove(actorDid);
        }
    }

    /// <summary>A read whose failure keeps the cache; returns whether its answer was cached.</summary>
    private async Task<bool> TryFetchAsync(string actorDid)
    {
        try
        {
            return (await FetchAsync(actorDid)).Applied;
        }
        catch (Exception)
        {
            if (ListsState != ListsState.Loaded)
            {
                ListsState = ListsState.Failed;
                Changed?.Invoke();
            }
            return false;
        }
    }

    /// <summary>
    /// Put <paramref name="actorDid"/> on the list or take them off it. Returns whether
    /// anything was written.
    /// </summary>
    public async Task<bool> SetMembershipAsync(string actorDid, string listUri, bool member)
    {
        await BeginWriteAsync();
        try
        {
            return await WriteAsync(actorDid, listUri, member);
        }
        finally
        {
            EndWrite();
        }
    }

    private async Task BeginWriteAsync()
    {
        if (!_isWriting)
        {
            _isWriting = true;
            return;
        }
        var turn = new TaskCompletionSource();
        _writeWaiters.Enqueue(turn);
        await turn.Task;
    }

    private void EndWrite()
    {
        if (_writeWaiters.TryDequeue(out var next)) next.SetResult();
        else _isWriting = false;
    }

    private async Task<bool> WriteAsync(string actorDid, string listUri, bool member)
    {
        var current = (await FetchAsync(actorDid)).Memberships;
        var target = current.FirstOrDefault(m => m.ListUri == listUri) ?? throw new ListNotFoundException(listUri);
        if (member && target.ItemUri is null)
        {
            var created = await editor.AddAsync(actorDid, listUri);
            Record(actorDid, listUri, new RecentWrite(Added: created, Removed: null, Now));
            return true;
        }
        if (!member && target.ItemUri is { } itemUri)
        {
            await editor.RemoveAsync(itemUri);
            Record(actorDid, listUri, new RecentWrite(Added: null, Removed: itemUri, Now));
            return true;
        }
        return false;
    }

    private void Record(string actorDid, string listUri, RecentWrite change)
    {
        BumpGeneration(actorDid);
        if (!_recentWrites.TryGetValue(actorDid, out var recent)) _recentWrites[actorDid] = recent = [];
        recent[listUri] = change;
        if (!_items.TryGetValue(actorDid, out var byList)) _items[actorDid] = byList = [];
        if (change.Added is { } created) byList[listUri] = created;
        else byList.Remove(listUri);
        if (!_checked.TryGetValue(actorDid, out var lists)) _checked[actorDid] = lists = [];
        lists.Add(listUri);
        Changed?.Invoke();
    }

    /// <summary>
    /// Read the server and cache the answer, unless a newer read or change for the actor
    /// came first. Returns the answer with recent changes laid over it (used by a change
    /// to decide).
    /// </summary>
    private async Task<(IReadOnlyList<CuratedListMembership> Memberships, bool Applied)> FetchAsync(string actorDid)
    {
        var generation = BumpGeneration(actorDid);
        var readNumber = ++_readsStarted;
        var answer = await editor.ListsWithMembershipAsync(actorDid);
        var memberships = OverlayRecentWrites(actorDid, answer);
        if (readNumber > _listsFilledBy)
        {
            _listsFilledBy = readNumber;
            Lists = memberships.Select(m => new CuratedList(m.ListUri, m.Name)).ToList();
            ListsState = ListsState.Loaded;
        }
        var applied = _generations[actorDid] == generation;
        if (applied)
        {
            _items[actorDid] = memberships
                .Where(m => m.ItemUri is not null)
                .ToDictionary(m => m.ListUri, m => m.ItemUri!);
            _checked[actorDid] = memberships.Select(m => m.ListUri).ToHashSet();
        }
        Changed?.Invoke();
        return (memberships, applied);
    }

    private IReadOnlyList<CuratedListMembership> OverlayRecentWrites(
        string actorDid, IReadOnlyList<CuratedListMembership> answer)
    {
        if (!_recentWrites.TryGetValue(actorDid, out var recent)) return answer;
        var cutoff = Now - RecentWriteWindow;
        foreach (var stale in recent.Where(r => r.Value.At <= cutoff).Select(r => r.Key).ToList()) recent.Remove(stale);
        if (recent.Count == 0) return answer;
        return answer.Select(membership =>
        {
            if (!recent.TryGetValue(membership.ListUri, out var change)) return membership;
            var item = change.Added is { } created
                ? membership.ItemUri ?? created
                : membership.ItemUri == change.Removed ? null : membership.ItemUri;
            return membership with { ItemUri = item };
        }).ToList();
    }

    private int BumpGeneration(string actorDid)
    {
        var next = _generations.GetValueOrDefault(actorDid) + 1;
        _generations[actorDid] = next;
        return next;
    }
}
