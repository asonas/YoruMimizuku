using System.Net;
using YoruMimizuku.Core.OAuth;

namespace YoruMimizuku.Core.Accounts;

/// <summary>
/// Sends requests to <c>did</c>'s PDS as that account: the access token with a DPoP
/// proof from the account's key, one retry on a nonce challenge, and on a 401 a token
/// refresh shared with every other request of the account, then one retry. Requests
/// to any other host go out untouched. The account is looked up at each request, so
/// a client built before the account signs in again keeps working, and one built
/// before it signs out throws <see cref="UnknownAccountException"/>.
/// <code>
/// new XrpcClient(did, accounts.GetPds(did),
///     new HttpClient(new AccountHandler(accounts, did) { InnerHandler = new SocketsHttpHandler() }))
/// </code>
/// </summary>
public sealed class AccountHandler(AccountManager accounts, string did) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var account = accounts.State(did);
        if (!account.Serves(request.RequestUri!)) return await base.SendAsync(request, cancellationToken);

        var tokens = account.Tokens;
        var response = await DPoPSender.SendAsync(base.SendAsync, request, account.Key, account.Nonces, tokens.AccessToken, cancellationToken);
        if (response.StatusCode != HttpStatusCode.Unauthorized
            || tokens.RefreshToken is null
            || await DPoPSender.IsNonceChallengeAsync(response, cancellationToken))
            return response;

        var fresh = await account.RefreshAsync(tokens).WaitAsync(cancellationToken);
        response.Dispose();
        return await DPoPSender.SendAsync(base.SendAsync, request, account.Key, account.Nonces, fresh.AccessToken, cancellationToken);
    }
}
