namespace YoruMimizuku.Core;

/// <summary>Profiles, as seen by the account.</summary>
public sealed class ProfileService(XrpcClient xrpc)
{
    /// <summary><c>app.bsky.actor.getProfile</c> for <paramref name="actor"/>, a DID or handle.</summary>
    public Task<ProfileViewBasic> GetProfileAsync(string actor, CancellationToken cancellationToken = default) =>
        xrpc.QueryAsync("app.bsky.actor.getProfile", [("actor", actor)], ProfileViewBasic.FromJson, cancellationToken);

    /// <summary>The account's own avatar URL, or null when it has none.</summary>
    public async Task<string?> GetAvatarAsync(CancellationToken cancellationToken = default) =>
        (await GetProfileAsync(xrpc.Did, cancellationToken)).Avatar;
}
