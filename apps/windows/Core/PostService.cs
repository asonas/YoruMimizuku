using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace YoruMimizuku.Core;

/// <summary>A record's address and version (<c>com.atproto.repo.strongRef</c>).</summary>
public sealed record StrongRef(string Uri, string Cid);

/// <summary>An image to attach, as encoded bytes, with its alt text.</summary>
public sealed record DraftImage(byte[] Data, string MimeType, string Alt);

/// <summary>
/// A video to attach, as the file's bytes, sent as-is (no transcoding). The width and
/// height give the embed's aspect ratio; either may be unknown.
/// </summary>
public sealed record DraftVideo(byte[] Data, string MimeType, string Filename, string Alt, int? Width, int? Height);

/// <summary>
/// A post to publish. <paramref name="ReplyParentUri"/> is the post it answers;
/// <paramref name="Quote"/> is the post it quotes. A <paramref name="Video"/> takes the
/// media slot, so any <paramref name="Images"/> are then left out.
/// </summary>
public sealed record PostDraft(
    string Text,
    IReadOnlyList<DraftImage>? Images = null,
    string? ReplyParentUri = null,
    StrongRef? Quote = null,
    DraftVideo? Video = null);

/// <summary>Reading and writing posts as the account. Records go to the account's own repo.</summary>
/// <param name="videos">Uploads a draft's video; a draft with a video fails without it.</param>
public sealed class PostService(XrpcClient xrpc, TimeProvider? clock = null, VideoUploadService? videos = null) : IPostsService
{
    private const string Post = "app.bsky.feed.post";
    private const string Like = "app.bsky.feed.like";
    private const string Repost = "app.bsky.feed.repost";

    public async Task<GetPostsResponse> GetPostsAsync(IReadOnlyList<string> uris, CancellationToken cancellationToken)
    {
        if (uris.Count == 0) return new GetPostsResponse([]);
        return await xrpc.QueryAsync(
            "app.bsky.feed.getPosts",
            uris.Select(uri => ("uris", (string?)uri)),
            GetPostsResponse.FromJson,
            cancellationToken);
    }

    /// <summary>
    /// Publishes <paramref name="draft"/>. Trailing whitespace is dropped from the text.
    /// Images are uploaded first, in order; a video instead goes to the video service
    /// under a service-auth token from the PDS, and is embedded once processed. Links,
    /// hashtags and mentions become facets; a mention whose handle does not resolve to a
    /// DID stays plain text. A reply joins the
    /// parent's conversation: its root is the parent's root, or the parent when the parent
    /// is not itself a reply.
    /// </summary>
    public async Task<StrongRef> CreatePostAsync(PostDraft draft, CancellationToken cancellationToken = default)
    {
        var text = PostText.TrimTrailingWhitespace(draft.Text);

        var media = draft.Video is { } video
            ? await VideoEmbedAsync(video, cancellationToken)
            : await ImagesEmbedAsync(draft.Images ?? [], cancellationToken);

        var facets = new JsonArray();
        foreach (var facet in FacetDetector.Detect(text))
        {
            if (await FeatureAsync(facet.Feature, cancellationToken) is not { } feature) continue;
            facets.Add(new JsonObject
            {
                ["index"] = new JsonObject { ["byteStart"] = facet.ByteStart, ["byteEnd"] = facet.ByteEnd },
                ["features"] = new JsonArray(feature),
            });
        }

        var record = new JsonObject { ["$type"] = Post, ["text"] = text, ["createdAt"] = Now() };
        if (facets.Count > 0) record["facets"] = facets;
        if (Embed(media, draft.Quote) is { } embed) record["embed"] = embed;
        if (draft.ReplyParentUri is { } parentUri) record["reply"] = await ReplyAsync(parentUri, cancellationToken);
        return await CreateRecordAsync(Post, record, cancellationToken);
    }

    /// <summary>Deletes the account's own post at <paramref name="uri"/>.</summary>
    public Task DeletePostAsync(string uri, CancellationToken cancellationToken = default) =>
        DeleteRecordAsync(Post, uri, cancellationToken);

    /// <summary>Likes <paramref name="subject"/>, returning the like record's URI, which <see cref="UnlikeAsync"/> takes.</summary>
    public async Task<string> LikeAsync(StrongRef subject, CancellationToken cancellationToken = default) =>
        (await CreateRecordAsync(Like, Subject(Like, subject), cancellationToken)).Uri;

    public Task UnlikeAsync(string likeUri, CancellationToken cancellationToken = default) =>
        DeleteRecordAsync(Like, likeUri, cancellationToken);

    /// <summary>Reposts <paramref name="subject"/>, returning the repost record's URI, which <see cref="UnrepostAsync"/> takes.</summary>
    public async Task<string> RepostAsync(StrongRef subject, CancellationToken cancellationToken = default) =>
        (await CreateRecordAsync(Repost, Subject(Repost, subject), cancellationToken)).Uri;

    public Task UnrepostAsync(string repostUri, CancellationToken cancellationToken = default) =>
        DeleteRecordAsync(Repost, repostUri, cancellationToken);

    /// <summary>Mutes <paramref name="actorDid"/> for the account (<c>app.bsky.graph.muteActor</c>). Mutes are private to the viewer.</summary>
    public Task MuteActorAsync(string actorDid, CancellationToken cancellationToken = default) =>
        xrpc.ProcedureAsync("app.bsky.graph.muteActor", XrpcClient.Json(new JsonObject { ["actor"] = actorDid }), cancellationToken);

    /// <summary>The record at <paramref name="uri"/> exactly as stored in its repo (<c>com.atproto.repo.getRecord</c>).</summary>
    public Task<RecordResponse> GetRecordAsync(string uri, CancellationToken cancellationToken = default)
    {
        var address = AtUri.Parse(uri) ?? throw new ArgumentException($"Not a record URI: {uri}", nameof(uri));
        return xrpc.QueryAsync(
            "com.atproto.repo.getRecord",
            [("repo", address.Repo), ("collection", address.Collection), ("rkey", address.Rkey)],
            RecordResponse.FromJson,
            cancellationToken);
    }

    private async Task<JsonObject?> FeatureAsync(DetectedFeature feature, CancellationToken cancellationToken) =>
        feature switch
        {
            DetectedFeature.Link link => new JsonObject { ["$type"] = "app.bsky.richtext.facet#link", ["uri"] = link.Uri },
            DetectedFeature.Tag tag => new JsonObject { ["$type"] = "app.bsky.richtext.facet#tag", ["tag"] = tag.Name },
            DetectedFeature.MentionCandidate mention =>
                await ResolveDidAsync(mention.Handle, cancellationToken) is { } did
                    ? new JsonObject { ["$type"] = "app.bsky.richtext.facet#mention", ["did"] = did }
                    : null,
            _ => null,
        };

    /// <summary>The DID behind <paramref name="handle"/>, or null when the server cannot resolve it.</summary>
    private async Task<string?> ResolveDidAsync(string handle, CancellationToken cancellationToken)
    {
        try
        {
            return await xrpc.QueryAsync(
                "app.bsky.actor.getProfile", [("actor", handle)], json => json.RequiredString("did"), cancellationToken);
        }
        catch (HttpRequestException error) when (error.StatusCode is not null)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private async Task<JsonObject> ReplyAsync(string parentUri, CancellationToken cancellationToken)
    {
        var parent = await GetRecordAsync(parentUri, cancellationToken);
        var parentRef = new StrongRef(parent.Uri, parent.Cid ?? throw new JsonException("The parent record has no cid."));
        var root = JsonFields.Tolerant(() => parent.Value.Optional("reply")?.Optional("root") is { } json
            ? new StrongRef(json.RequiredString("uri"), json.RequiredString("cid"))
            : null);
        return new JsonObject { ["root"] = Ref(root ?? parentRef), ["parent"] = Ref(parentRef) };
    }

    /// <summary>Uploads each image to the PDS; the images embed, or null for none.</summary>
    private async Task<JsonObject?> ImagesEmbedAsync(IReadOnlyList<DraftImage> draftImages, CancellationToken cancellationToken)
    {
        var images = new JsonArray();
        foreach (var image in draftImages)
        {
            var blob = await xrpc.ProcedureAsync(
                "com.atproto.repo.uploadBlob",
                XrpcClient.Bytes(image.Data, image.MimeType),
                json => JsonNode.Parse(json.Required("blob").GetRawText())!,
                cancellationToken);
            images.Add(new JsonObject { ["image"] = blob, ["alt"] = image.Alt });
        }
        return images.Count > 0 ? new JsonObject { ["$type"] = "app.bsky.embed.images", ["images"] = images } : null;
    }

    /// <summary>
    /// Asks the PDS for a 30-minute token that lets the video service upload the blob
    /// on the account's behalf, uploads the video, waits for processing, and returns
    /// the video embed. An empty alt text is left out.
    /// </summary>
    private async Task<JsonObject> VideoEmbedAsync(DraftVideo video, CancellationToken cancellationToken)
    {
        var uploader = videos ?? throw new InvalidOperationException("This post service cannot upload videos.");
        var expires = (clock ?? TimeProvider.System).GetUtcNow().AddMinutes(30).ToUnixTimeSeconds();
        var token = await xrpc.QueryAsync(
            "com.atproto.server.getServiceAuth",
            [
                ("aud", VideoUploadService.Audience(xrpc.Pds)),
                ("lxm", "com.atproto.repo.uploadBlob"),
                ("exp", expires.ToString(CultureInfo.InvariantCulture)),
            ],
            json => json.RequiredString("token"),
            cancellationToken);
        var job = await uploader.UploadVideoAsync(token, xrpc.Did, video.Filename, video.Data, video.MimeType, cancellationToken);
        var blob = await uploader.PollUntilCompleteAsync(job.JobId, token, cancellationToken: cancellationToken);

        var embed = new JsonObject { ["$type"] = "app.bsky.embed.video", ["video"] = blob };
        if (video is { Width: { } width, Height: { } height })
            embed["aspectRatio"] = new JsonObject { ["width"] = width, ["height"] = height };
        if (video.Alt.Length > 0) embed["alt"] = video.Alt;
        return embed;
    }

    /// <summary>The embed for media (images or a video), a quote, or both; null for neither.</summary>
    private static JsonObject? Embed(JsonObject? media, StrongRef? quote)
    {
        if (quote is null) return media;
        var record = new JsonObject { ["$type"] = "app.bsky.embed.record", ["record"] = Ref(quote) };
        return media is null
            ? record
            : new JsonObject { ["$type"] = "app.bsky.embed.recordWithMedia", ["record"] = record, ["media"] = media };
    }

    private JsonObject Subject(string type, StrongRef subject) =>
        new() { ["$type"] = type, ["subject"] = Ref(subject), ["createdAt"] = Now() };

    private static JsonObject Ref(StrongRef value) => new() { ["uri"] = value.Uri, ["cid"] = value.Cid };

    private Task<StrongRef> CreateRecordAsync(string collection, JsonObject record, CancellationToken cancellationToken) =>
        xrpc.CreateRecordAsync(collection, record, cancellationToken);

    private Task DeleteRecordAsync(string collection, string recordUri, CancellationToken cancellationToken) =>
        xrpc.DeleteRecordAsync(collection, recordUri, cancellationToken);

    private string Now() => RepoRecords.Timestamp(clock);
}
