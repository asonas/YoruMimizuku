namespace YoruMimizuku.Core;

/// <summary>
/// The authors a window's account muted while the window is open (この人をミュート).
/// Windows builds a timeline each time it is shown, so the window, not each timeline,
/// remembers them: every timeline drops their posts from the pages it fetches, and
/// the timelines on screen drop the posts they show when <see cref="AuthorMuted"/> is
/// raised. The port of the Swift TimelineViewModel.removePosts(byAuthor:).
/// </summary>
public sealed class MutedAuthors
{
    private readonly HashSet<string> _dids = [];

    /// <summary>Raised with the DID the first time an author is muted.</summary>
    public event Action<string>? AuthorMuted;

    public void Mute(string did)
    {
        if (_dids.Add(did)) AuthorMuted?.Invoke(did);
    }

    /// <summary>Whether the post at <paramref name="postUri"/> is by a muted author.</summary>
    public bool Hides(string postUri) => AtUri.Parse(postUri) is { } address && _dids.Contains(address.Repo);

    /// <summary>Forget every mute, when the window signs in as another account.</summary>
    public void Clear() => _dids.Clear();
}
