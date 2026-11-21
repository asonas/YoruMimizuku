namespace YoruMimizuku.Core;

/// <summary>The account's notifications.</summary>
public sealed class NotificationService(XrpcClient xrpc)
{
    /// <summary>
    /// A page of <c>app.bsky.notification.listNotifications</c>. It asks for every
    /// notification: left unset, <c>priority</c> falls back to the account setting, which
    /// drops notifications from accounts the viewer does not follow.
    /// </summary>
    public Task<ListNotificationsResponse> ListNotificationsAsync(
        string? cursor = null, int limit = 50, CancellationToken cancellationToken = default) =>
        xrpc.QueryAsync(
            "app.bsky.notification.listNotifications",
            [("limit", XrpcClient.Number(limit)), ("priority", "false"), ("cursor", cursor)],
            ListNotificationsResponse.FromJson,
            cancellationToken);

    /// <summary>
    /// The newest page as notifications-tab rows, with the liked or reposted post's text and
    /// thumbnail filled in. When those posts fail to load, the rows come back without them.
    /// </summary>
    public async Task<IReadOnlyList<NotificationGroup>> LoadGroupsAsync(CancellationToken cancellationToken = default)
    {
        var page = await ListNotificationsAsync(cancellationToken: cancellationToken);
        var groups = NotificationGroup.Group(page.Notifications);
        try
        {
            return await NotificationSubjects.HydrateAsync(groups, new PostService(xrpc), cancellationToken);
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            return groups;
        }
    }
}
