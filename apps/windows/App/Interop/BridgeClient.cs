using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;

namespace YoruMimizuku.App.Interop;

/// <summary>Thrown when the bridge returns <c>{ "ok": false, "error": ... }</c>.
/// Carries the shared LoadFailure classification (kind) and friendly title/message
/// when present, so a view can show a tailored failed state with a retry.</summary>
public sealed class BridgeException : Exception
{
    public string? Kind { get; }
    public string? Title { get; }
    public string? FriendlyMessage { get; }
    /// <summary>True when the stored session is no longer valid (invalid_grant on a
    /// refresh) and the app should drop it and return to login.</summary>
    public bool SessionExpired { get; }

    public BridgeException(string message, string? kind = null, string? title = null,
        string? friendlyMessage = null, bool sessionExpired = false)
        : base(message)
    {
        Kind = kind;
        Title = title;
        FriendlyMessage = friendlyMessage;
        SessionExpired = sessionExpired;
    }

    public static BridgeException FromEnvelope(JsonObject node) =>
        new(
            node["error"]?.GetValue<string>() ?? "unknown bridge error",
            node["kind"]?.GetValue<string>(),
            node["title"]?.GetValue<string>(),
            node["message"]?.GetValue<string>(),
            node["sessionExpired"]?.GetValue<bool>() ?? false);
}

/// <summary>
/// Managed, async-friendly facade over <see cref="NativeMethods"/>. Each call
/// runs the blocking native function on a background thread, parses the
/// <c>{ ok, data }</c> envelope, and returns the strongly-typed payload.
/// </summary>
public sealed class BridgeClient : ICoreClient
{
    public static ICoreClient Shared { get; } = new BridgeClient();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private BridgeClient() { }

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

    public Task SwitchAccountAsync(string did) =>
        CallVoidAsync(NativeMethods.yoru_account_switch, new { did });

    public Task<List<AccountSummaryDto>> AccountSummariesAsync() =>
        CallAsync<List<AccountSummaryDto>>(NativeMethods.yoru_account_summaries, new { })!;

    public Task<NextAccountDto> RemoveAndAdvanceAsync(string did) =>
        CallAsync<NextAccountDto>(NativeMethods.yoru_account_remove_advance, new { did })!;

    // -- Login (split for WebView2) --

    public Task<LoginBeginDto> LoginBeginAsync(string handle) =>
        CallAsync<LoginBeginDto>(NativeMethods.yoru_login_begin, new { handle })!;

    public Task<AccountDto> LoginCompleteAsync(string pendingId, string callbackUrl) =>
        CallAsync<AccountDto>(NativeMethods.yoru_login_complete, new { pendingId, callbackUrl })!;

    // -- Account-free --

    public Task<PermalinkDto> PostPermalinkAsync(string id, string authorHandle) =>
        CallAsync<PermalinkDto>(NativeMethods.yoru_post_permalink, new { id, authorHandle })!;

    public Task<LinkCardDto?> OgpLoadAsync(string url) =>
        CallAsync<LinkCardDto>(NativeMethods.yoru_ogp_load, new { url });

    public Task<List<ArrangeResultDto>> FeedArrangeAsync(object items) =>
        CallAsync<List<ArrangeResultDto>>(NativeMethods.yoru_feed_arrange, new { items })!;

    public IAccountClient ForAccount(string did) => new AccountClient(did);

    /// <summary>Adds <c>did</c> to every request, so the bridge acts as this
    /// account instead of the store's current one.</summary>
    private sealed class AccountClient(string did) : IAccountClient
    {
        public string Did { get; } = did;

        public Task<TimelinePageDto> TimelineLoadAsync(string? cursor = null) =>
            CallAsync<TimelinePageDto>(NativeMethods.yoru_timeline_load, Scoped(new { cursor }))!;

        public Task<TimelinePageDto> AuthorFeedLoadAsync(string actor, string? cursor = null) =>
            CallAsync<TimelinePageDto>(NativeMethods.yoru_author_feed_load, Scoped(new { actor, cursor }))!;

        public Task<ConversationThreadDto> ThreadLoadAsync(string uri) =>
            CallAsync<ConversationThreadDto>(NativeMethods.yoru_thread_load, Scoped(new { uri }))!;

        public Task<List<NotificationGroupDto>> NotificationsLoadAsync() =>
            CallAsync<List<NotificationGroupDto>>(NativeMethods.yoru_notifications_load, Scoped(new { }))!;

        public Task<TimelinePageDto> SearchLoadAsync(JsonObject filter, string? cursor = null) =>
            CallAsync<TimelinePageDto>(NativeMethods.yoru_search_load, Scoped(new { filter, cursor }))!;

        public Task<PostResultDto> PostCreateAsync(object draft) =>
            CallAsync<PostResultDto>(NativeMethods.yoru_post_create, Scoped(draft))!;

        public Task<RecordRefDto> LikeAsync(string uri, string cid) =>
            CallAsync<RecordRefDto>(NativeMethods.yoru_post_like, Scoped(new { uri, cid }))!;

        public Task UnlikeAsync(string recordUri) =>
            CallVoidAsync(NativeMethods.yoru_post_unlike, Scoped(new { recordUri }));

        public Task<RecordRefDto> RepostAsync(string uri, string cid) =>
            CallAsync<RecordRefDto>(NativeMethods.yoru_post_repost, Scoped(new { uri, cid }))!;

        public Task UnrepostAsync(string recordUri) =>
            CallVoidAsync(NativeMethods.yoru_post_unrepost, Scoped(new { recordUri }));

        public Task DeletePostAsync(string uri) =>
            CallVoidAsync(NativeMethods.yoru_post_delete, Scoped(new { uri }));

        public Task<AvatarDto> AvatarAsync() =>
            CallAsync<AvatarDto>(NativeMethods.yoru_profile_avatar, Scoped(new { }))!;

        public Task<ProfileDto> ProfileAsync(string actor) =>
            CallAsync<ProfileDto>(NativeMethods.yoru_profile_load, Scoped(new { actor }))!;

        private JsonObject Scoped(object request)
        {
            var node = JsonSerializer.SerializeToNode(request, JsonOptions)!.AsObject();
            node["did"] = Did;
            return node;
        }
    }

    // -- Plumbing --

    private static Task<T?> CallAsync<T>(Func<string, IntPtr> fn, object request) =>
        Task.Run(() =>
        {
            var json = NativeMethods.Consume(fn(JsonSerializer.Serialize(request, JsonOptions)));
            var node = JsonNode.Parse(json)!.AsObject();
            if (node["ok"]?.GetValue<bool>() != true)
            {
                throw BridgeException.FromEnvelope(node);
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
                throw BridgeException.FromEnvelope(node);
            }
        });
}
