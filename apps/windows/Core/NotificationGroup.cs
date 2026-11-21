namespace YoruMimizuku.Core;

/// <summary>One person in a notification row, such as one of the people who liked a post.</summary>
public sealed record NotificationActor(string DisplayName, string Handle, Uri? AvatarUrl);

/// <summary>
/// A notifications-tab row. Likes of one post collapse into one row, as do reposts of
/// one post ("5 people liked your post"); every other notification is its own row.
/// <paramref name="SubjectUri"/> is the post a reaction targets; its text and first
/// image are filled in after the post is fetched.
/// <paramref name="Text"/> is the body of a reply, mention or quote.
/// </summary>
public sealed record NotificationGroup(
    string Id,
    NotificationReason Reason,
    IReadOnlyList<NotificationActor> Actors,
    string? SubjectUri,
    string? SubjectText,
    Uri? SubjectImageUrl,
    string? Text,
    DateTimeOffset LatestCreatedAt,
    bool IsRead)
{
    /// <summary>
    /// The Bluesky-style summary, such as "aliceおよび他2人があなたの投稿をいいねしました":
    /// the lead actor, the others as a count, then what they did.
    /// </summary>
    public string ActionSummary
    {
        get
        {
            var lead = Actors.FirstOrDefault()?.DisplayName ?? "";
            var others = Math.Max(0, Actors.Count - 1);
            var subject = others > 0 ? $"{lead}および他{others}人" : lead;
            return subject + Reason switch
            {
                NotificationReason.Like => "があなたの投稿をいいねしました",
                NotificationReason.Repost => "があなたの投稿をリポストしました",
                NotificationReason.Follow => "があなたをフォローしました",
                NotificationReason.Mention => "があなたにメンションしました",
                NotificationReason.Reply => "があなたの投稿に返信しました",
                NotificationReason.Quote => "があなたの投稿を引用しました",
                _ => "のアクティビティがありました",
            };
        }
    }

    /// <summary>
    /// Collapses a notifications page into rows, in the order each row first appears
    /// (the API's newest-first order). A row is read only when all its notifications
    /// are, and carries the newest of their times.
    /// </summary>
    public static IReadOnlyList<NotificationGroup> Group(IReadOnlyList<BskyNotification> notifications) =>
        notifications
            .GroupBy(Key)
            .Select(members =>
            {
                var first = members.First();
                return new NotificationGroup(
                    members.Key,
                    first.Reason,
                    members.Select(n => new NotificationActor(
                        DisplayName.Of(n.Author), n.Author.Handle, DisplayUrl.Parse(n.Author.Avatar))).ToList(),
                    first.ReasonSubject,
                    null,
                    null,
                    first.RecordText,
                    members.Max(n => Timestamp.Parse(n.IndexedAt)),
                    members.All(n => n.IsRead));
            })
            .ToList();

    private static string Key(BskyNotification notification) =>
        (notification.Reason, notification.ReasonSubject) switch
        {
            (NotificationReason.Like, { } subject) => $"like|{subject}",
            (NotificationReason.Repost, { } subject) => $"repost|{subject}",
            _ => $"single|{notification.Uri}|{notification.Cid}",
        };
}
