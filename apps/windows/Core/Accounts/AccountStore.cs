using System.Text.Json;
using YoruMimizuku.Core.OAuth;

namespace YoruMimizuku.Core.Accounts;

/// <summary>A signed-in account as stored: its tokens and its DPoP private key as PKCS#8.</summary>
internal sealed record StoredAccount(string Did, string? Handle, Uri Pds, string Issuer, OAuthTokens Tokens, byte[] DPoPKey)
{
    public override string ToString() => $"StoredAccount {{ Did = {Did} }}";
}

/// <summary>The stored accounts in sign-in order, and the one a new window opens.</summary>
internal sealed record AccountsIndex(IReadOnlyList<string> Dids, string? Current);

/// <summary>
/// Accounts in an <see cref="ISecureStorage"/>: "accounts.index", and "account.&lt;did&gt;"
/// per account. One lock covers every read-modify-write, so windows that sign out,
/// switch and refresh at once never lose each other's writes.
/// </summary>
internal sealed class AccountStore(ISecureStorage storage)
{
    private const string IndexKey = "accounts.index";
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private readonly object _gate = new();

    public AccountsIndex Index()
    {
        lock (_gate) return ReadIndex();
    }

    public StoredAccount? Find(string did)
    {
        lock (_gate) return Read(did);
    }

    /// <summary>Stores the account, replacing one with the same DID, and lists it once.</summary>
    public void Save(StoredAccount account)
    {
        lock (_gate)
        {
            Write(account);
            var index = ReadIndex();
            if (!index.Dids.Contains(account.Did)) WriteIndex(index with { Dids = [.. index.Dids, account.Did] });
        }
    }

    public void SetCurrent(string did)
    {
        lock (_gate)
        {
            var index = ReadIndex();
            if (!index.Dids.Contains(did)) throw new UnknownAccountException(did);
            WriteIndex(index with { Current = did });
        }
    }

    public void Remove(string did)
    {
        lock (_gate)
        {
            storage.Delete(AccountKey(did));
            var index = ReadIndex();
            WriteIndex(new AccountsIndex([.. index.Dids.Where(d => d != did)], index.Current == did ? null : index.Current));
        }
    }

    /// <summary>
    /// Replaces the account's tokens only while it still holds <paramref name="expected"/>.
    /// False when the account was removed or holds other tokens, as after a sign-in again.
    /// </summary>
    public bool ReplaceTokens(string did, OAuthTokens expected, OAuthTokens next)
    {
        lock (_gate)
        {
            if (Read(did) is not { } account || account.Tokens != expected) return false;
            Write(account with { Tokens = next });
            return true;
        }
    }

    private static string AccountKey(string did) => "account." + did;

    private StoredAccount? Read(string did) =>
        storage.Read(AccountKey(did)) is { } data && JsonSerializer.Deserialize<AccountJson>(data, Json) is { } json
            ? new StoredAccount(json.Did, json.Handle, new Uri(json.Pds), json.Issuer,
                new OAuthTokens(json.AccessToken, json.RefreshToken, json.Scope), json.DPoPKey)
            : null;

    private void Write(StoredAccount account) =>
        storage.Write(AccountKey(account.Did), JsonSerializer.SerializeToUtf8Bytes(new AccountJson(
            account.Did, account.Handle, account.Pds.AbsoluteUri, account.Issuer,
            account.Tokens.AccessToken, account.Tokens.RefreshToken, account.Tokens.Scope, account.DPoPKey), Json));

    private AccountsIndex ReadIndex() =>
        storage.Read(IndexKey) is { } data && JsonSerializer.Deserialize<AccountsIndex>(data, Json) is { } index
            ? index
            : new AccountsIndex([], null);

    private void WriteIndex(AccountsIndex index) => storage.Write(IndexKey, JsonSerializer.SerializeToUtf8Bytes(index, Json));

    private sealed record AccountJson(
        string Did, string? Handle, string Pds, string Issuer, string AccessToken, string? RefreshToken, string Scope, byte[] DPoPKey);
}
