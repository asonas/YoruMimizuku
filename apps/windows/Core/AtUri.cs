namespace YoruMimizuku.Core;

/// <summary>
/// A record address, <c>at://&lt;repo&gt;/&lt;collection&gt;/&lt;rkey&gt;</c>. The repo is
/// normally the author's DID; the rkey addresses a like or repost record for deletion.
/// </summary>
public sealed record AtUri(string Repo, string Collection, string Rkey)
{
    private const string Scheme = "at://";

    /// <summary>The parsed URI, or null unless the value has exactly three non-empty segments.</summary>
    public static AtUri? Parse(string value)
    {
        if (!value.StartsWith(Scheme, StringComparison.Ordinal)) return null;
        var parts = value[Scheme.Length..].Split('/');
        if (parts.Length != 3 || parts.Any(string.IsNullOrEmpty)) return null;
        return new AtUri(parts[0], parts[1], parts[2]);
    }
}
