namespace YoruMimizuku.Core;

/// <summary>The public bsky.app address of a post.</summary>
public static class PostPermalink
{
    /// <summary>
    /// <c>https://bsky.app/profile/{handle}/post/{rkey}</c> for the post at <paramref name="id"/>,
    /// an AT-URI. An empty or <c>handle.invalid</c> handle falls back to the author's DID.
    /// Null when <paramref name="id"/> is not a record address.
    /// </summary>
    public static Uri? Url(string id, string authorHandle)
    {
        if (AtUri.Parse(id) is not { } address) return null;
        var profile = authorHandle is "" or "handle.invalid" ? address.Repo : authorHandle;
        return Uri.TryCreate($"https://bsky.app/profile/{profile}/post/{address.Rkey}", UriKind.Absolute, out var url)
            ? url
            : null;
    }
}
