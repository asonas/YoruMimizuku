using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using YoruMimizuku.Core;

namespace YoruMimizuku.App.Interop;

/// <summary>
/// <see cref="IAccountClient"/> over the C# core, acting as the account behind
/// <paramref name="xrpc"/>. Results come back as the app's DTOs and failures as
/// <see cref="BridgeException"/>.
/// </summary>
/// <param name="isSessionExpired">
/// Recognizes the auth layer's "the session is gone" failure (an invalid_grant on
/// refresh) among the exceptions the account's HttpClient throws, and sets
/// <see cref="BridgeException.SessionExpired"/> for it. Until OAuth lands nothing
/// signals it, so the default recognizes nothing.
/// </param>
public sealed class CoreAccountClient(XrpcClient xrpc, Func<Exception, bool>? isSessionExpired = null) : IAccountClient
{
    /// <summary>What the bridge's thread endpoint builds: depths 0 to 3 below the focus.</summary>
    private const int ThreadReplyDepth = 3;

    private readonly FeedService feeds = new(xrpc);
    private readonly NotificationService notifications = new(xrpc);
    private readonly SearchService search = new(xrpc);
    private readonly PostService posts = new(xrpc);
    private readonly ProfileService profiles = new(xrpc);

    public string Did => xrpc.Did;

    public Task<TimelinePageDto> TimelineLoadAsync(string? cursor = null) =>
        Run(async () => Page(await feeds.GetTimelineAsync(cursor)));

    public Task<TimelinePageDto> AuthorFeedLoadAsync(string actor, string? cursor = null) =>
        Run(async () => Page(await feeds.GetAuthorFeedAsync(actor, cursor)));

    public Task<ConversationThreadDto> ThreadLoadAsync(string uri) =>
        Run(async () =>
        {
            var thread = (await feeds.GetPostThreadAsync(uri)).Thread;
            return new ConversationThreadDto(
                CoreDtos.Post(PostDisplay.From(thread)),
                ThreadNode.ChildTree(thread, ThreadReplyDepth).Select(CoreDtos.ThreadNode).ToList());
        });

    public Task<List<NotificationGroupDto>> NotificationsLoadAsync() =>
        Run(async () => (await notifications.LoadGroupsAsync()).Select(CoreDtos.NotificationGroup).ToList());

    public Task<TimelinePageDto> SearchLoadAsync(JsonObject filter, string? cursor = null) =>
        Run(async () =>
        {
            var page = await FilterSearch.LoadPageAsync(search, ParseFilter(filter), cursor);
            return new TimelinePageDto(page.Posts.Select(p => CoreDtos.Post(PostDisplay.From(p))).ToList(), page.Cursor);
        });

    public Task<PostResultDto> PostCreateAsync(object draft) =>
        Run(async () =>
        {
            var created = await posts.CreatePostAsync(ParseDraft(JsonSerializer.SerializeToElement(draft)));
            return new PostResultDto(created.Uri, created.Cid);
        });

    public Task<RecordRefDto> LikeAsync(string uri, string cid) =>
        Run(async () => new RecordRefDto(await posts.LikeAsync(new StrongRef(uri, cid))));

    public Task UnlikeAsync(string recordUri) => Run(() => posts.UnlikeAsync(recordUri));

    public Task<RecordRefDto> RepostAsync(string uri, string cid) =>
        Run(async () => new RecordRefDto(await posts.RepostAsync(new StrongRef(uri, cid))));

    public Task UnrepostAsync(string recordUri) => Run(() => posts.UnrepostAsync(recordUri));

    public Task DeletePostAsync(string uri) => Run(() => posts.DeletePostAsync(uri));

    public Task<AvatarDto> AvatarAsync() => Run(async () => new AvatarDto(await profiles.GetAvatarAsync()));

    public Task<ProfileDto> ProfileAsync(string actor) =>
        Run(async () => CoreDtos.Profile(await profiles.GetProfileAsync(actor)));

    private static TimelinePageDto Page(TimelineResponse response) =>
        new(response.Feed.Select(item => CoreDtos.Post(PostDisplay.From(item))).ToList(), response.Cursor);

    /// <summary>
    /// The SavedFilter object the app sends (<c>SavedFilterModel.ToBridgeJson</c>), read as
    /// the Swift bridge decodes it: camelCase keys, lowercase raw values, the combinator
    /// defaulting to <c>and</c>. <c>createdAt</c> plays no part in a search and is ignored.
    /// </summary>
    private static SavedFilter ParseFilter(JsonObject filter)
    {
        var json = JsonSerializer.SerializeToElement(filter);
        var terms = json.GetProperty("terms").EnumerateArray().Select(term => new FilterTerm(
            term.GetProperty("id").GetGuid(),
            term.GetProperty("kind").GetString() switch
            {
                "keyword" => FilterTermKind.Keyword,
                "user" => FilterTermKind.User,
                "hashtag" => FilterTermKind.Hashtag,
                "mention" => FilterTermKind.Mention,
                var kind => throw new JsonException($"Unknown filter term kind '{kind}'."),
            },
            term.GetProperty("value").GetString()!)).ToList();
        var combinator = json.TryGetProperty("combinator", out var value) ? value.GetString() : "and";
        return new SavedFilter(
            json.GetProperty("id").GetGuid(),
            json.GetProperty("name").GetString()!,
            terms,
            combinator switch
            {
                "and" => FilterCombinator.And,
                "or" => FilterCombinator.Or,
                _ => throw new JsonException($"Unknown filter combinator '{combinator}'."),
            },
            DateTimeOffset.UnixEpoch);
    }

    /// <summary>
    /// The draft the composer builds: <c>text</c>, <c>images</c> of
    /// <c>{ dataBase64, mimeType, alt }</c>, <c>replyParentURI</c> and <c>quote { uri, cid }</c>.
    /// As in the bridge, an image whose data is not valid base64 is left out.
    /// </summary>
    private static PostDraft ParseDraft(JsonElement draft)
    {
        var images = Optional(draft, "images") is { } array
            ? array.EnumerateArray()
                .Select(image => (
                    Data: Base64(image.GetProperty("dataBase64").GetString()!),
                    MimeType: image.GetProperty("mimeType").GetString()!,
                    Alt: image.GetProperty("alt").GetString()!))
                .Where(image => image.Data is not null)
                .Select(image => new DraftImage(image.Data!, image.MimeType, image.Alt))
                .ToList()
            : [];
        var quote = Optional(draft, "quote") is { } q
            ? new StrongRef(q.GetProperty("uri").GetString()!, q.GetProperty("cid").GetString()!)
            : null;
        return new PostDraft(
            draft.GetProperty("text").GetString()!,
            images,
            Optional(draft, "replyParentURI")?.GetString(),
            quote);
    }

    private static JsonElement? Optional(JsonElement json, string name) =>
        json.TryGetProperty(name, out var value) && value.ValueKind != JsonValueKind.Null ? value : null;

    private static byte[]? Base64(string value)
    {
        var buffer = new byte[value.Length];
        return Convert.TryFromBase64String(value, buffer, out var written) ? buffer[..written] : null;
    }

    private async Task<T> Run<T>(Func<Task<T>> call)
    {
        try
        {
            return await call().ConfigureAwait(false);
        }
        catch (Exception error)
        {
            throw Failure(error);
        }
    }

    private Task Run(Func<Task> call) => Run(async () =>
    {
        await call().ConfigureAwait(false);
        return true;
    });

    /// <summary>The bridge's error envelope: the LoadFailure classification, its friendly text and the raw detail.</summary>
    private BridgeException Failure(Exception error)
    {
        var failure = LoadFailure.From(error);
        var kind = failure.Kind switch
        {
            LoadFailureKind.Offline => "offline",
            LoadFailureKind.RateLimited => "rateLimited",
            LoadFailureKind.Server => "server",
            _ => "unknown",
        };
        return new BridgeException(failure.Detail, kind, failure.Title, failure.Message, isSessionExpired?.Invoke(error) ?? false);
    }
}
