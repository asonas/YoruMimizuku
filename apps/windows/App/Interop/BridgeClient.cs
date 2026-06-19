using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;

namespace YoruMimizuku.App.Interop;

/// <summary>Thrown when the bridge returns <c>{ "ok": false, "error": ... }</c>.</summary>
public sealed class BridgeException : Exception
{
    public BridgeException(string message) : base(message) { }
}

/// <summary>
/// Managed, async-friendly facade over <see cref="NativeMethods"/>. Each call
/// runs the blocking native function on a background thread, parses the
/// <c>{ ok, data }</c> envelope, and returns the strongly-typed payload.
/// </summary>
public sealed class BridgeClient
{
    public static BridgeClient Shared { get; } = new();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    // -- Lifecycle --

    public Task InitializeAsync(string service, string clientId, string redirectUri, string scope) =>
        CallVoidAsync(NativeMethods.yoru_init, new
        {
            service,
            clientID = clientId,
            redirectURI = redirectUri,
            scope
        });

    // -- Account --

    public async Task<AccountDto?> CurrentAccountAsync()
    {
        var wrapper = await CallAsync<OptionalAccountDto>(NativeMethods.yoru_account_current, new { });
        return wrapper?.Account;
    }

    public Task<List<string>> ListAccountsAsync() =>
        CallAsync<List<string>>(NativeMethods.yoru_account_list, new { })!;

    public Task SwitchAccountAsync(string did) =>
        CallVoidAsync(NativeMethods.yoru_account_switch, new { did });

    public Task RemoveAccountAsync(string did) =>
        CallVoidAsync(NativeMethods.yoru_account_remove, new { did });

    // -- Login (split for WebView2) --

    public Task<LoginBeginDto> LoginBeginAsync(string handle) =>
        CallAsync<LoginBeginDto>(NativeMethods.yoru_login_begin, new { handle })!;

    public Task<AccountDto> LoginCompleteAsync(string pendingId, string callbackUrl) =>
        CallAsync<AccountDto>(NativeMethods.yoru_login_complete, new { pendingId, callbackUrl })!;

    // -- Feeds --

    public Task<TimelinePageDto> TimelineLoadAsync(string? cursor = null) =>
        CallAsync<TimelinePageDto>(NativeMethods.yoru_timeline_load, new { cursor })!;

    public Task<TimelinePageDto> AuthorFeedLoadAsync(string actor, string? cursor = null) =>
        CallAsync<TimelinePageDto>(NativeMethods.yoru_author_feed_load, new { actor, cursor })!;

    public Task<ConversationThreadDto> ThreadLoadAsync(string uri) =>
        CallAsync<ConversationThreadDto>(NativeMethods.yoru_thread_load, new { uri })!;

    public Task<List<NotificationGroupDto>> NotificationsLoadAsync() =>
        CallAsync<List<NotificationGroupDto>>(NativeMethods.yoru_notifications_load, new { })!;

    /// <summary>Run a saved filter. <paramref name="filter"/> is the SavedFilter JSON object.</summary>
    public Task<TimelinePageDto> SearchLoadAsync(JsonObject filter, string? cursor = null) =>
        CallAsync<TimelinePageDto>(NativeMethods.yoru_search_load, new { filter, cursor })!;

    // -- Compose --

    public Task<PostResultDto> PostCreateAsync(object draft) =>
        CallAsync<PostResultDto>(NativeMethods.yoru_post_create, draft)!;

    // -- Interactions --

    public Task<RecordRefDto> LikeAsync(string uri, string cid) =>
        CallAsync<RecordRefDto>(NativeMethods.yoru_post_like, new { uri, cid })!;

    public Task UnlikeAsync(string recordUri) =>
        CallVoidAsync(NativeMethods.yoru_post_unlike, new { recordUri });

    public Task<RecordRefDto> RepostAsync(string uri, string cid) =>
        CallAsync<RecordRefDto>(NativeMethods.yoru_post_repost, new { uri, cid })!;

    public Task UnrepostAsync(string recordUri) =>
        CallVoidAsync(NativeMethods.yoru_post_unrepost, new { recordUri });

    public Task<PermalinkDto> PostPermalinkAsync(string id, string authorHandle) =>
        CallAsync<PermalinkDto>(NativeMethods.yoru_post_permalink, new { id, authorHandle })!;

    /// <summary>Delete the viewer's own post record (app.bsky.feed.post). <paramref name="uri"/> is the post AT-URI.</summary>
    public Task DeletePostAsync(string uri) =>
        CallVoidAsync(NativeMethods.yoru_post_delete, new { uri });

    // -- Profile --

    public Task<AvatarDto> AvatarAsync() =>
        CallAsync<AvatarDto>(NativeMethods.yoru_profile_avatar, new { })!;

    public Task<ProfileDto> ProfileAsync(string actor) =>
        CallAsync<ProfileDto>(NativeMethods.yoru_profile_load, new { actor })!;

    // -- Link previews / feed grouping --

    /// <summary>Fetch an OGP preview card for a bare URL; null when the page yields no usable metadata.</summary>
    public Task<LinkCardDto?> OgpLoadAsync(string url) =>
        CallAsync<LinkCardDto>(NativeMethods.yoru_ogp_load, new { url });

    /// <summary>Group a feed page web-style. <paramref name="items"/> carries each post's id, createdAt, and replyParentId.</summary>
    public Task<List<ArrangeResultDto>> FeedArrangeAsync(object items) =>
        CallAsync<List<ArrangeResultDto>>(NativeMethods.yoru_feed_arrange, new { items })!;

    // -- Plumbing --

    private static Task<T?> CallAsync<T>(Func<string, IntPtr> fn, object request) =>
        Task.Run(() =>
        {
            var json = NativeMethods.Consume(fn(JsonSerializer.Serialize(request, JsonOptions)));
            var node = JsonNode.Parse(json)!.AsObject();
            if (node["ok"]?.GetValue<bool>() != true)
            {
                throw new BridgeException(node["error"]?.GetValue<string>() ?? "unknown bridge error");
            }
            var data = node["data"];
            return data is null ? default : data.Deserialize<T>(JsonOptions);
        });

    private static Task CallVoidAsync(Func<string, IntPtr> fn, object request) =>
        Task.Run(() =>
        {
            var json = NativeMethods.Consume(fn(JsonSerializer.Serialize(request, JsonOptions)));
            var node = JsonNode.Parse(json)!.AsObject();
            if (node["ok"]?.GetValue<bool>() != true)
            {
                throw new BridgeException(node["error"]?.GetValue<string>() ?? "unknown bridge error");
            }
        });
}
