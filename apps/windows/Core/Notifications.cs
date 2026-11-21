using System.Text.Json;
using static YoruMimizuku.Core.JsonFields;

namespace YoruMimizuku.Core;

/// <summary>Response of <c>app.bsky.notification.listNotifications</c>.</summary>
public sealed record ListNotificationsResponse(IReadOnlyList<BskyNotification> Notifications, string? Cursor)
{
    public static ListNotificationsResponse FromJson(JsonElement json) =>
        new(json.RequiredArray("notifications", BskyNotification.FromJson), json.OptionalString("cursor"));
}

/// <summary>
/// One notification. <paramref name="ReasonSubject"/> is the post a reaction targets
/// (absent for a follow). <paramref name="RecordText"/> is the text of the record
/// that caused it, present for replies, mentions and quotes.
/// </summary>
public sealed record BskyNotification(
    string Uri,
    string Cid,
    ProfileViewBasic Author,
    NotificationReason Reason,
    string? ReasonSubject,
    string? RecordText,
    bool IsRead,
    string IndexedAt)
{
    public static BskyNotification FromJson(JsonElement json)
    {
        var record = json.Required("record");
        return new BskyNotification(
            json.RequiredString("uri"),
            json.RequiredString("cid"),
            ProfileViewBasic.FromJson(json.Required("author")),
            NotificationReason.FromRaw(json.RequiredString("reason")),
            json.OptionalString("reasonSubject"),
            Tolerant(() => record.OptionalString("text")),
            json.OptionalBool("isRead") ?? false,
            json.RequiredString("indexedAt"));
    }
}

/// <summary>
/// Why a notification was generated. A reason the app does not know (a future
/// lexicon value) reads as <see cref="Other"/> so the page still decodes.
/// </summary>
public abstract record NotificationReason
{
    private NotificationReason() { }

    public sealed record Like : NotificationReason;

    public sealed record Repost : NotificationReason;

    public sealed record Follow : NotificationReason;

    public sealed record Mention : NotificationReason;

    public sealed record Reply : NotificationReason;

    public sealed record Quote : NotificationReason;

    public sealed record Other(string Raw) : NotificationReason;

    public static NotificationReason FromRaw(string raw) => raw switch
    {
        "like" => new Like(),
        "repost" => new Repost(),
        "follow" => new Follow(),
        "mention" => new Mention(),
        "reply" => new Reply(),
        "quote" => new Quote(),
        _ => new Other(raw),
    };
}
