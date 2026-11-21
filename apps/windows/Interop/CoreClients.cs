using System;
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

    /// <summary>
    /// Raised with the account's DID when one of its calls finds the refresh token dead
    /// (invalid_grant), on whichever thread the call ran. The account stays stored, so
    /// signing in to it again replaces its tokens in place.
    /// </summary>
    event Action<string>? SessionExpired;
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

    /// <summary>The feeds and lists the account pinned (savedFeedsPrefV2), in pin order.</summary>
    Task<List<SavedFeedDto>> PinnedFeedsLoadAsync();

    /// <summary>A page of a pinned feed's or list's timeline.</summary>
    Task<TimelinePageDto> SavedFeedLoadAsync(SavedFeedDto source, string? cursor = null);

    /// <summary>
    /// The account's curated lists and who is on them, for "リストに追加" and for
    /// dropping an avatar on a pinned list. One per account, so the account's windows
    /// share its cache and take turns writing. Use it from the UI thread.
    /// </summary>
    YoruMimizuku.Core.ListMembershipModel ListMembership { get; }

    /// <summary>Run a saved filter. <paramref name="filter"/> is the SavedFilter JSON object.</summary>
    Task<TimelinePageDto> SearchLoadAsync(JsonObject filter, string? cursor = null);

    Task<PostResultDto> PostCreateAsync(object draft);
    Task<RecordRefDto> LikeAsync(string uri, string cid);
    Task UnlikeAsync(string recordUri);
    Task<RecordRefDto> RepostAsync(string uri, string cid);
    Task UnrepostAsync(string recordUri);

    /// <summary>Delete this account's own post record (app.bsky.feed.post). <paramref name="uri"/> is the post AT-URI.</summary>
    Task DeletePostAsync(string uri);

    /// <summary>Mute <paramref name="actorDid"/> for this account (app.bsky.graph.muteActor).</summary>
    Task MuteActorAsync(string actorDid);

    /// <summary>The record at <paramref name="uri"/> as stored in its repo, as indented JSON with sorted keys.</summary>
    Task<string> RecordLoadAsync(string uri);

    Task<AvatarDto> AvatarAsync();
    Task<ProfileDto> ProfileAsync(string actor);
}
