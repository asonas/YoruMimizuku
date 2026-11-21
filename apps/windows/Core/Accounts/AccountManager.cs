using YoruMimizuku.Core.OAuth;

namespace YoruMimizuku.Core.Accounts;

/// <summary>An account as the switcher shows it: no tokens, no key.</summary>
public sealed record AccountSummary(string Did, string? Handle);

public sealed class UnknownAccountException(string did) : Exception($"No stored account for {did}.")
{
    public string Did { get; } = did;
}

/// <summary>
/// The signed-in accounts: sign-in in two steps around WebView2, the account list,
/// the current account a new window opens, switching and signing out.
/// </summary>
public sealed class AccountManager
{
    private readonly AccountStore _store;
    private readonly OAuthLogin _login;

    /// <param name="transport">Carries sign-in, discovery and token refresh.</param>
    public AccountManager(ISecureStorage storage, HttpMessageHandler transport, OAuthClientConfig config)
    {
        _store = new AccountStore(storage);
        _login = new OAuthLogin(new HttpMessageInvoker(transport, disposeHandler: false), new DPoPNonces(), config);
    }

    /// <summary>Starts sign-in for a handle or DID; open the result's authorization URL in WebView2.</summary>
    public Task<PendingLogin> BeginLoginAsync(string handleOrDid, CancellationToken cancellationToken = default) =>
        _login.BeginAsync(handleOrDid, cancellationToken);

    /// <summary>
    /// Finishes sign-in with the as.ason:/callback URL WebView2 navigated to, stores the
    /// account with its DPoP key, and makes it current.
    /// </summary>
    public async Task<AccountSummary> CompleteLoginAsync(PendingLogin pending, string callbackUrl, CancellationToken cancellationToken = default)
    {
        var tokens = await _login.CompleteAsync(pending, callbackUrl, cancellationToken);
        _store.Save(new StoredAccount(pending.Did, pending.Handle, pending.Pds, pending.Issuer, tokens, pending.Key.ExportPkcs8()));
        _store.SetCurrent(pending.Did);
        return new AccountSummary(pending.Did, pending.Handle);
    }

    /// <summary>The account a new window or a relaunch opens, or null when none is signed in.</summary>
    public AccountSummary? CurrentAccount() =>
        _store.Index().Current is { } did && _store.Find(did) is { } account ? Summary(account) : null;

    /// <summary>Every stored account in sign-in order.</summary>
    public IReadOnlyList<AccountSummary> Summaries() =>
        [.. _store.Index().Dids.Select(_store.Find).OfType<StoredAccount>().Select(Summary)];

    public void SwitchTo(string did) => _store.SetCurrent(did);

    /// <summary>
    /// Signs <paramref name="did"/> out and makes the first remaining account current;
    /// returns it, or null when none remain.
    /// </summary>
    public string? RemoveAndAdvance(string did)
    {
        _store.Remove(did);
        var next = _store.Index().Dids.FirstOrDefault();
        if (next is not null) _store.SetCurrent(next);
        return next;
    }

    /// <summary>The account's PDS, the only host its requests are authorized for.</summary>
    public Uri GetPds(string did) => (_store.Find(did) ?? throw new UnknownAccountException(did)).Pds;

    private static AccountSummary Summary(StoredAccount account) => new(account.Did, account.Handle);
}
