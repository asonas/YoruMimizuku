namespace YoruMimizuku.Core.OAuth;

/// <summary>
/// A sign-in waiting for the browser: open <see cref="AuthorizationUrl"/> in WebView2
/// and hand the callback URL back to complete it. The PKCE verifier, state and DPoP
/// key stay inside.
/// </summary>
public sealed class PendingLogin
{
    internal PendingLogin(string handle, DiscoveredAccount account, DPoPKey key, Pkce pkce, string state, Uri authorizationUrl)
    {
        Handle = handle;
        Account = account;
        Key = key;
        Pkce = pkce;
        State = state;
        AuthorizationUrl = authorizationUrl;
    }

    public Uri AuthorizationUrl { get; }

    /// <summary>What the user typed: a handle, or a DID.</summary>
    internal string Handle { get; }

    internal DiscoveredAccount Account { get; }
    internal DPoPKey Key { get; }
    internal Pkce Pkce { get; }
    internal string State { get; }

    internal string Did => Account.Did;
    internal Uri Pds => Account.Pds;
    internal string Issuer => Account.Server.Issuer;
}
