using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Threading.Tasks;
using YoruMimizuku.Core;
using YoruMimizuku.Core.Accounts;
using YoruMimizuku.Core.OAuth;

namespace YoruMimizuku.App.Interop;

/// <summary>
/// <see cref="ICoreClient"/> over the C# core. One instance serves the process: it owns
/// the account store, the sign-ins waiting for WebView2, and one
/// <see cref="CoreAccountClient"/> per account, so windows on the same DID share its
/// <see cref="HttpClient"/>.
/// </summary>
/// <param name="transport">
/// Carries every request: sign-in and refresh, each account's PDS calls behind its
/// <see cref="AccountHandler"/>, and OGP fetches. It is shared and never disposed.
/// </param>
public sealed class CoreClient(ISecureStorage storage, HttpMessageHandler transport, OAuthClientConfig config) : ICoreClient
{
    private readonly AccountManager accounts = new(storage, transport, config);
    private readonly LinkPreviewLoader previews = new(new HttpClient(transport, disposeHandler: false));
    // The video service takes a Bearer service-auth token, not the account's DPoP proof,
    // so it gets the bare transport. A large file can take longer than the default 100 s.
    private readonly VideoUploadService videos = new(new HttpClient(transport, disposeHandler: false) { Timeout = TimeSpan.FromMinutes(10) });
    private readonly ConcurrentDictionary<string, PendingLogin> pendingLogins = new();
    private readonly ConcurrentDictionary<string, IAccountClient> accountClients = new();

    public Task<AccountDto?> CurrentAccountAsync() =>
        Task.Run(() => accounts.CurrentAccount() is { } account ? new AccountDto(account.Did, account.Handle) : null);

    public Task<List<AccountSummaryDto>> AccountSummariesAsync() =>
        Task.Run(() => accounts.Summaries().Select(account => new AccountSummaryDto(account.Did, account.Handle)).ToList());

    public Task SwitchAccountAsync(string did) => Task.Run(() => accounts.SwitchTo(did));

    public Task<NextAccountDto> RemoveAndAdvanceAsync(string did) =>
        Task.Run(() =>
        {
            var next = accounts.RemoveAndAdvance(did);
            accountClients.TryRemove(did, out _);
            return new NextAccountDto(next);
        });

    public async Task<LoginBeginDto> LoginBeginAsync(string handle)
    {
        var pending = await accounts.BeginLoginAsync(handle).ConfigureAwait(false);
        var pendingId = Guid.NewGuid().ToString("N");
        pendingLogins[pendingId] = pending;
        return new LoginBeginDto(pendingId, pending.AuthorizationUrl.AbsoluteUri, config.CallbackScheme);
    }

    /// <summary>Each pending sign-in completes at most once, whether or not the exchange succeeds.</summary>
    public async Task<AccountDto> LoginCompleteAsync(string pendingId, string callbackUrl)
    {
        if (!pendingLogins.TryRemove(pendingId, out var pending))
            throw new InvalidOperationException("This sign-in has already finished or was never started.");
        var account = await accounts.CompleteLoginAsync(pending, callbackUrl).ConfigureAwait(false);
        // Signing in again may have moved the account to another PDS.
        accountClients.TryRemove(account.Did, out _);
        return new AccountDto(account.Did, account.Handle);
    }

    public Task<PermalinkDto> PostPermalinkAsync(string id, string authorHandle) =>
        Task.FromResult(CoreOperations.PostPermalink(id, authorHandle));

    public Task<LinkCardDto?> OgpLoadAsync(string url) => CoreOperations.OgpLoadAsync(previews, url);

    public Task<List<ArrangeResultDto>> FeedArrangeAsync(IReadOnlyList<ArrangeItemDto> items) =>
        Task.FromResult(CoreOperations.FeedArrange(items));

    /// <summary>Throws <see cref="UnknownAccountException"/> when <paramref name="did"/> is not signed in.</summary>
    public IAccountClient ForAccount(string did) =>
        accountClients.GetOrAdd(did, d => new CoreAccountClient(
            new XrpcClient(d, accounts.GetPds(d), new HttpClient(new AccountHandler(accounts, d) { InnerHandler = transport })),
            error => error is OAuthException { IsSessionExpired: true },
            videos));
}
