using System.Collections.Generic;
using System.Text.Json.Nodes;
using System.Threading.Tasks;

namespace YoruMimizuku.App.Interop;

/// <summary>
/// App-level core operations: the account store, sign-in, and the calls that
/// need no account. One instance serves every window.
/// </summary>
public interface ICoreClient
{
    /// <summary>The store's current account: the one a new window or a relaunch opens.</summary>
    Task<AccountDto?> CurrentAccountAsync();

    /// <summary>Token-free account list for the switcher menu (DID + handle).</summary>
    Task<List<AccountSummaryDto>> AccountSummariesAsync();

    Task SwitchAccountAsync(string did);

    /// <summary>Remove an account and advance to the next one; NextDid is null when none remain.</summary>
    Task<NextAccountDto> RemoveAndAdvanceAsync(string did);

    Task<LoginBeginDto> LoginBeginAsync(string handle);
    Task<AccountDto> LoginCompleteAsync(string pendingId, string callbackUrl);

    Task<PermalinkDto> PostPermalinkAsync(string id, string authorHandle);

    /// <summary>Fetch an OGP preview card for a bare URL; null when the page yields no usable metadata.</summary>
    Task<LinkCardDto?> OgpLoadAsync(string url);

    /// <summary>Group a newest-first feed page web-style.</summary>
    Task<List<ArrangeResultDto>> FeedArrangeAsync(IReadOnlyList<ArrangeItemDto> items);

    /// <summary>A client whose every request acts as <paramref name="did"/>,
    /// whichever account the store marks current.</summary>
    IAccountClient ForAccount(string did);
}

/// <summary>
/// Operations that act as one signed-in account. A window holds the client for
/// its own account, so its reads and writes never follow another window's switch.
/// </summary>
public interface IAccountClient
{
    string Did { get; }

    Task<TimelinePageDto> TimelineLoadAsync(string? cursor = null);
    Task<TimelinePageDto> AuthorFeedLoadAsync(string actor, string? cursor = null);
    Task<ConversationThreadDto> ThreadLoadAsync(string uri);
    Task<List<NotificationGroupDto>> NotificationsLoadAsync();

    /// <summary>Run a saved filter. <paramref name="filter"/> is the SavedFilter JSON object.</summary>
    Task<TimelinePageDto> SearchLoadAsync(JsonObject filter, string? cursor = null);

    Task<PostResultDto> PostCreateAsync(object draft);
    Task<RecordRefDto> LikeAsync(string uri, string cid);
    Task UnlikeAsync(string recordUri);
    Task<RecordRefDto> RepostAsync(string uri, string cid);
    Task UnrepostAsync(string recordUri);

    /// <summary>Delete this account's own post record (app.bsky.feed.post). <paramref name="uri"/> is the post AT-URI.</summary>
    Task DeletePostAsync(string uri);

    Task<AvatarDto> AvatarAsync();
    Task<ProfileDto> ProfileAsync(string actor);
}
