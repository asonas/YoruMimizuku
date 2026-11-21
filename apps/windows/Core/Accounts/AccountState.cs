using YoruMimizuku.Core.OAuth;

namespace YoruMimizuku.Core.Accounts;

/// <summary>One signed-in account in memory: its DPoP key, its PDS and its current tokens.</summary>
internal sealed class AccountState
{
    private readonly object _gate = new();
    private readonly string _issuer;
    private readonly AccountStore _store;
    private readonly HttpMessageInvoker _http;
    private readonly OAuthClientConfig _config;
    private OAuthTokens _tokens;
    private Task<OAuthTokens>? _refreshing;

    public AccountState(StoredAccount account, AccountStore store, HttpMessageInvoker http, DPoPNonces nonces, OAuthClientConfig config)
    {
        Did = account.Did;
        Pds = account.Pds;
        Key = DPoPKey.FromPkcs8(account.DPoPKey);
        Nonces = nonces;
        _issuer = account.Issuer;
        _tokens = account.Tokens;
        _store = store;
        _http = http;
        _config = config;
    }

    public string Did { get; }
    public Uri Pds { get; }
    public DPoPKey Key { get; }
    public DPoPNonces Nonces { get; }

    public OAuthTokens Tokens
    {
        get { lock (_gate) return _tokens; }
    }

    public bool Serves(Uri uri) =>
        Uri.Compare(uri, Pds, UriComponents.SchemeAndServer, UriFormat.SafeUnescaped, StringComparison.OrdinalIgnoreCase) == 0;

    /// <summary>
    /// Tokens newer than <paramref name="stale"/>, the ones a refused request used. While
    /// they are still current, one refresh runs and every caller awaits it; once they are
    /// not, the current tokens come back without a refresh, so a late refusal of old
    /// tokens never spends a refresh token or writes older tokens over newer ones.
    /// </summary>
    public Task<OAuthTokens> RefreshAsync(OAuthTokens stale)
    {
        lock (_gate)
        {
            if (_tokens != stale) return Task.FromResult(_tokens);
            return _refreshing ??= RefreshOnceAsync(stale);
        }
    }

    /// <summary>
    /// Refreshes <paramref name="used"/> and saves the rotated tokens before any caller
    /// retries, since the old refresh token is spent once the server answers. The save
    /// is skipped when the store no longer holds <paramref name="used"/>. The account is
    /// locked against other app processes throughout; when the store already holds other
    /// tokens, one of them refreshed first, and those are taken as they are, since
    /// refreshing <paramref name="used"/> would replay a spent token.
    /// </summary>
    private async Task<OAuthTokens> RefreshOnceAsync(OAuthTokens used)
    {
        await Task.Yield();
        OAuthTokens? next = null;
        try
        {
            using var timeout = new CancellationTokenSource(AccountManager.NetworkTimeout);
            await using var locked = await _store.LockAccountAsync(Did, timeout.Token);
            if (_store.Find(Did) is { } stored && stored.Tokens != used) return next = stored.Tokens;

            var server = await OAuthDiscovery.FetchAuthorizationServerAsync(_http, _issuer, timeout.Token);
            var issued = await TokenEndpoint.RefreshAsync(_http, Key, Nonces, server, _config, used.RefreshToken!, Did, timeout.Token);
            next = issued with { RefreshToken = issued.RefreshToken ?? used.RefreshToken };
            _store.ReplaceTokens(Did, used, next);
            return next;
        }
        finally
        {
            lock (_gate)
            {
                if (next is not null) _tokens = next;
                _refreshing = null;
            }
        }
    }
}
