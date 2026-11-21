using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using YoruMimizuku.Core;

namespace YoruMimizuku.App.Interop;

/// <summary>
/// The account-free <see cref="ICoreClient"/> operations over the C# core, returning the
/// app's DTOs, for <see cref="CoreClient"/> to call.
/// </summary>
public static class CoreOperations
{
    /// <summary>The post's bsky.app address; <see cref="PermalinkDto.Url"/> is null when <paramref name="id"/> is not an AT-URI.</summary>
    public static PermalinkDto PostPermalink(string id, string authorHandle) =>
        new(Core.PostPermalink.Url(id, authorHandle)?.OriginalString);

    /// <summary>
    /// The OGP card for a bare URL, or null when the URL does not parse or the page has no
    /// usable metadata. <paramref name="previews"/> caches per URL, so the caller keeps one
    /// for the process, as the bridge does.
    /// </summary>
    public static async Task<LinkCardDto?> OgpLoadAsync(LinkPreviewLoader previews, string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var parsed) && await previews.PreviewAsync(parsed) is { } card
            ? CoreDtos.LinkCard(card)
            : null;

    /// <summary>
    /// Groups a newest-first feed page web-style. Unlike the bridge, which sends no
    /// authors, a reply joins its parent's block only when both have the same author.
    /// </summary>
    public static List<ArrangeResultDto> FeedArrange(IReadOnlyList<ArrangeItemDto> items) =>
        FeedThreading.Arrange(items.Select(item => new ThreadingPost(
                item.Id, item.AuthorDid, ParseTime(item.CreatedAt), item.ReplyParentId)).ToList())
            .Select(row => new ArrangeResultDto(row.Id, row.ConnectsToPrevious, row.ConnectsToNext))
            .ToList();

    /// <summary>A DTO time back to a date; the Unix epoch when unparseable, as in the bridge.</summary>
    private static DateTimeOffset ParseTime(string value) =>
        DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date)
            ? date
            : DateTimeOffset.UnixEpoch;
}
