using System.Collections.Concurrent;
using YoruMimizuku.Core.Accounts;
using YoruMimizuku.Core.OAuth;

namespace YoruMimizuku.Core.Tests;

internal sealed class InMemorySecureStorage : ISecureStorage
{
    private readonly ConcurrentDictionary<string, byte[]> _items = new();
    private readonly ConcurrentDictionary<string, SemaphoreSlim> _locks = new();

    public byte[]? Read(string key) => _items.TryGetValue(key, out var value) ? value : null;
    public void Write(string key, byte[] value) => _items[key] = value;
    public void Delete(string key) => _items.TryRemove(key, out _);

    public async Task<IAsyncDisposable> LockAsync(string key, CancellationToken cancellationToken)
    {
        var gate = _locks.GetOrAdd(key, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(cancellationToken);
        return new Release(gate);
    }

    private sealed class Release(SemaphoreSlim gate) : IAsyncDisposable
    {
        public ValueTask DisposeAsync()
        {
            gate.Release();
            return ValueTask.CompletedTask;
        }
    }
}

internal static class AccountTestSupport
{
    public static AccountManager Manager(FakeAtproto server, ISecureStorage? storage = null) =>
        new(storage ?? new InMemorySecureStorage(), server, OAuthClientConfig.YoruMimizuku);

    /// <summary>Signs in through the fake's browser step, as the login view does with WebView2.</summary>
    public static async Task<AccountSummary> SignInAsync(
        this AccountManager accounts, FakeAtproto server, string handle = "alice.test", string signedInAs = FakeAtproto.AliceDid)
    {
        var pending = await accounts.BeginLoginAsync(handle);
        return await accounts.CompleteLoginAsync(pending, server.Approve(pending.AuthorizationUrl, signedInAs));
    }
}
