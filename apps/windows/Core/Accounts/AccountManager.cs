using System.Collections.Concurrent;
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
    /// <summary>How long a sign-in step or a token refresh may take, as URLSession allows the Swift core.</summary>
    internal static readonly TimeSpan NetworkTimeout = TimeSpan.FromSeconds(60);

    private readonly AccountStore _store;
    private readonly HttpMessageInvoker _http;
    private readonly DPoPNonces _nonces = new();
    private readonly OAuthClientConfig _config;
    private readonly OAuthLogin _login;
    private readonly ConcurrentDictionary<string, AccountState> _states = new();

    /// <param name="transport">
    /// Carries sign-in, discovery and token refresh. PDS requests go through each
    /// <see cref="AccountHandler"/>'s own inner handler.
    /// </param>
    public AccountManager(ISecureStorage storage, HttpMessageHandler transport, OAuthClientConfig config)
    {
        _store = new AccountStore(storage);
        _http = new HttpMessageInvoker(transport, disposeHandler: false);
        _config = config;
        _login = new OAuthLogin(_http, _nonces, config);
    }

    /// <summary>Starts sign-in for a handle or DID; open the result's authorization URL in WebView2.</summary>
    public async Task<PendingLogin> BeginLoginAsync(string handleOrDid, CancellationToken cancellationToken = default)
    {
        using var timeout = Timeout(cancellationToken);
        return await _login.BeginAsync(handleOrDid, timeout.Token);
    }

    /// <summary>
    /// Finishes sign-in with the as.ason:/callback URL WebView2 navigated to, stores the
    /// account with its DPoP key, and makes it current.
    /// </summary>
    public async Task<AccountSummary> CompleteLoginAsync(PendingLogin pending, string callbackUrl, CancellationToken cancellationToken = default)
    {
        using var timeout = Timeout(cancellationToken);
        var tokens = await _login.CompleteAsync(pending, callbackUrl, timeout.Token);
        _store.Save(new StoredAccount(pending.Did, pending.Handle, pending.Pds, pending.Issuer, tokens, pending.Key.ExportPkcs8()));
        _store.SetCurrent(pending.Did);
        _states.TryRemove(pending.Did, out _);
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
        _states.TryRemove(did, out _);
        var next = _store.Index().Dids.FirstOrDefault();
        if (next is not null) _store.SetCurrent(next);
        return next;
    }

    /// <summary>The account's PDS, the only host its requests are authorized for.</summary>
    public Uri GetPds(string did) => (_store.Find(did) ?? throw new UnknownAccountException(did)).Pds;

    /// <summary>
    /// The one in-memory state per account, shared by every <see cref="AccountHandler"/>
    /// for it, so their refreshes coalesce. A sign-in again or a sign-out drops it.
    /// </summary>
    internal AccountState State(string did) =>
        _states.GetOrAdd(did, d => new AccountState(_store.Find(d) ?? throw new UnknownAccountException(d), _store, _http, _nonces, _config));

    private static AccountSummary Summary(StoredAccount account) => new(account.Did, account.Handle);

    private static CancellationTokenSource Timeout(CancellationToken cancellationToken)
    {
        var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(NetworkTimeout);
        return timeout;
    }
}
