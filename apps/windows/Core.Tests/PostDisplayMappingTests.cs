namespace YoruMimizuku.Core.Tests;

public class PostDisplayMappingTests
{
    private static PostView Post(
        string uri = "at://did:plc:alice/app.bsky.feed.post/aaa",
        string did = "did:plc:alice",
        string handle = "alice.bsky.social",
        string? displayName = "Alice",
        string? avatar = null,
        bool isVerified = false,
        string cid = "cid",
        string text = "hello",
        string createdAt = "2026-06-04T12:00:00.000Z",
        IReadOnlyList<Facet>? facets = null,
        int? replyCount = null,
        int? repostCount = null,
        int? likeCount = null,
        PostEmbed? embed = null,
        PostViewerState? viewer = null,
        IReadOnlyList<Label>? labels = null) =>
        new(
            uri,
            cid,
            new ProfileViewBasic(did, handle, displayName, avatar, isVerified),
            new PostRecord(text, createdAt, facets ?? []),
            replyCount,
            repostCount,
            likeCount,
            "2026-06-04T12:00:01.000Z",
            embed,
            viewer,
            labels ?? []);

    private static PostDisplay Feed(PostView post) => PostDisplay.From(new FeedViewPost(post, null, null));

    private static PostEmbed Embed(
        IReadOnlyList<EmbedImage>? images = null,
        EmbedExternal? external = null,
        EmbedVideo? video = null,
        EmbedRecord? record = null) =>
        new(images ?? [], external, video, record);

    [Fact]
    public void CarriesTheAuthorVerification()
    {
        Assert.True(Feed(Post(isVerified: true)).AuthorIsVerified);
        Assert.False(Feed(Post()).AuthorIsVerified);
    }

    [Fact]
    public void MapsPlainPost()
    {
        var display = Feed(Post(text: "hi there", replyCount: 1, repostCount: 2, likeCount: 3));

        Assert.Equal("at://did:plc:alice/app.bsky.feed.post/aaa", display.Id);
        Assert.Equal("did:plc:alice", display.AuthorDid);
        Assert.Equal("Alice", display.AuthorDisplayName);
        Assert.Equal("alice.bsky.social", display.AuthorHandle);
        Assert.Equal("hi there", display.Body);
        Assert.Null(display.ContextLabel);
        Assert.Equal(1, display.ReplyCount);
        Assert.Equal(2, display.RepostCount);
        Assert.Equal(3, display.LikeCount);
    }

    [Fact]
    public void MapsAdultSelfLabelToMediaWarning()
    {
        var display = Feed(Post(labels: [new Label("porn", "did:plc:alice", null)]));

        Assert.Equal(MediaWarning.Adult, display.MediaWarning);
    }

    [Fact]
    public void MapsGraphicMediaLabelToGraphicWarning()
    {
        var display = Feed(Post(labels: [new Label("graphic-media", "did:plc:labeler", null)]));

        Assert.Equal(MediaWarning.Graphic, display.MediaWarning);
    }

    [Theory]
    [InlineData("sexual")]
    [InlineData("nudity")]
    public void MapsSexualAndNudityLabelsToAdultWarning(string value)
    {
        Assert.Equal(MediaWarning.Adult, Feed(Post(labels: [new Label(value, null, null)])).MediaWarning);
    }

    [Fact]
    public void PostWithoutSensitiveLabelHasNoMediaWarning()
    {
        Assert.Null(Feed(Post()).MediaWarning);
        Assert.Null(Feed(Post(labels: [new Label("spam", null, null)])).MediaWarning);
    }

    [Fact]
    public void NegatedLabelDoesNotTriggerMediaWarning()
    {
        var display = Feed(Post(labels: [new Label("porn", "did:plc:labeler", true)]));

        Assert.Null(display.MediaWarning);
    }

    [Fact]
    public void MapsExternalEmbedToLinkCard()
    {
        var external = new EmbedExternal(
            "https://www.example.com/article", "An Article", "Worth reading.", "https://cdn.example/thumb.jpg");

        var card = Feed(Post(text: "see https://example.com/article", embed: Embed(external: external))).LinkCard;

        Assert.NotNull(card);
        Assert.Equal(new Uri("https://www.example.com/article"), card.Url);
        Assert.Equal("An Article", card.Title);
        Assert.Equal("Worth reading.", card.Description);
        Assert.Equal(new Uri("https://cdn.example/thumb.jpg"), card.ThumbUrl);
        Assert.Equal("example.com", card.Host);
    }

    [Fact]
    public void PostWithoutExternalEmbedHasNoLinkCard()
    {
        Assert.Null(Feed(Post()).LinkCard);
    }

    [Fact]
    public void ExternalEmbedWithNonWebUriProducesNoLinkCard()
    {
        // A hostile post could point the card at file:// or an app scheme, so that
        // tapping it hands that URL to the system opener. Such an embed has no card.
        var external = new EmbedExternal("file:///etc/passwd", "Local", "", null);

        Assert.Null(Feed(Post(embed: Embed(external: external))).LinkCard);
    }

    [Fact]
    public void ExternalEmbedWithWebUriStillProducesCard()
    {
        var external = new EmbedExternal("https://example.com/article", "Article", "", null);

        Assert.Equal(new Uri("https://example.com/article"), Feed(Post(embed: Embed(external: external))).LinkCard?.Url);
    }

    [Fact]
    public void MapsCidAndViewerState()
    {
        var display = Feed(Post(
            cid: "bafyreialice",
            viewer: new PostViewerState("at://did:plc:me/app.bsky.feed.like/xyz", null)));

        Assert.Equal("bafyreialice", display.Cid);
        Assert.Equal("at://did:plc:me/app.bsky.feed.like/xyz", display.ViewerLikeUri);
        Assert.True(display.IsLiked);
        Assert.Null(display.ViewerRepostUri);
        Assert.False(display.IsReposted);
    }

    [Fact]
    public void NoViewerMapsToNotLikedNotReposted()
    {
        var display = Feed(Post());

        Assert.Null(display.ViewerLikeUri);
        Assert.Null(display.ViewerRepostUri);
        Assert.False(display.IsLiked);
        Assert.False(display.IsReposted);
    }

    [Fact]
    public void FallsBackToHandleAndZeroCountsWhenAbsent()
    {
        var display = Feed(Post(displayName: null));

        Assert.Equal("alice.bsky.social", display.AuthorDisplayName);
        Assert.Null(display.AvatarUrl);
        Assert.Equal(0, display.ReplyCount);
        Assert.Equal(0, display.RepostCount);
        Assert.Equal(0, display.LikeCount);
    }

    [Theory]
    [InlineData("")]
    [InlineData("  ")]
    public void ABlankDisplayNameFallsBackToTheHandle(string displayName)
    {
        Assert.Equal("alice.bsky.social", Feed(Post(displayName: displayName)).AuthorDisplayName);
    }

    [Fact]
    public void MapsAvatarUrl()
    {
        var display = Feed(Post(avatar: "https://cdn.example/alice.jpg"));

        Assert.Equal(new Uri("https://cdn.example/alice.jpg"), display.AvatarUrl);
    }

    [Fact]
    public void MapsImageEmbedWithAspectRatio()
    {
        var images = new[]
        {
            new EmbedImage("https://cdn.example/t1.jpg", "https://cdn.example/f1.jpg", "cat", new ImageAspectRatio(1600, 900)),
            new EmbedImage("https://cdn.example/t2.jpg", "https://cdn.example/f2.jpg", "", null),
        };

        var display = Feed(Post(text: "look", embed: Embed(images: images)));

        Assert.Equal(2, display.Images.Count);
        Assert.Equal(new Uri("https://cdn.example/t1.jpg"), display.Images[0].ThumbUrl);
        Assert.Equal(new Uri("https://cdn.example/f1.jpg"), display.Images[0].FullsizeUrl);
        Assert.Equal("cat", display.Images[0].Alt);
        Assert.Equal(1600.0 / 900.0, display.Images[0].AspectRatio!.Value, 4);
        Assert.Null(display.Images[1].AspectRatio);
    }

    [Fact]
    public void NoEmbedMapsToNoImages()
    {
        Assert.Empty(Feed(Post()).Images);
    }

    [Fact]
    public void MapsReplyParent()
    {
        var parent = Post(
            uri: "at://did:plc:bob/app.bsky.feed.post/parent",
            did: "did:plc:bob",
            handle: "bob.bsky.social",
            displayName: "Bob",
            text: "original question");

        var display = PostDisplay.From(new FeedViewPost(Post(text: "agreed!"), null, new ReplyRef(parent)));

        Assert.NotNull(display.ReplyParent);
        Assert.Equal("bob.bsky.social", display.ReplyParent.AuthorHandle);
        Assert.Equal("original question", display.ReplyParent.Body);
        Assert.Equal("at://did:plc:bob/app.bsky.feed.post/parent", display.ReplyParent.Id);
    }

    [Fact]
    public void NoReplyMapsToNoReplyParent()
    {
        Assert.Null(Feed(Post()).ReplyParent);
    }

    [Fact]
    public void MapsThreadViewPostWithParent()
    {
        var parent = Post(uri: "at://did:plc:alice/app.bsky.feed.post/root", text: "起点の投稿");
        var focus = Post(
            uri: "at://did:plc:bob/app.bsky.feed.post/reply",
            did: "did:plc:bob",
            handle: "bob.bsky.social",
            displayName: "Bob",
            text: "返信");

        var display = PostDisplay.From(new ThreadViewPost(focus, new ThreadViewPost(parent, null, []), []));

        Assert.Equal("at://did:plc:bob/app.bsky.feed.post/reply", display.Id);
        Assert.Equal("返信", display.Body);
        Assert.Equal("alice.bsky.social", display.ReplyParent?.AuthorHandle);
        Assert.Equal("起点の投稿", display.ReplyParent?.Body);
    }

    [Fact]
    public void MapsThreadViewPostFullAncestorChain()
    {
        var root = new ThreadViewPost(Post(uri: "at://p/root", text: "親"), null, []);
        var mid = new ThreadViewPost(Post(uri: "at://p/mid", handle: "bob.bsky.social", text: "子"), root, []);
        var leaf = new ThreadViewPost(Post(uri: "at://p/leaf", handle: "carol.bsky.social", text: "孫"), mid, []);

        var display = PostDisplay.From(leaf);

        Assert.Equal("at://p/leaf", display.Id);
        Assert.Equal("at://p/mid", display.ReplyParent?.Id);
        Assert.Equal("at://p/root", display.ReplyParent?.ReplyParent?.Id);
        Assert.Null(display.ReplyParent?.ReplyParent?.ReplyParent);
    }

    [Fact]
    public void MapsThreadViewPostWithoutParent()
    {
        var display = PostDisplay.From(new ThreadViewPost(Post(text: "起点"), null, []));

        Assert.Null(display.ReplyParent);
    }

    [Fact]
    public void RepostReasonBecomesContextLabel()
    {
        var reason = new ReasonRepost(
            new ProfileViewBasic("did:plc:bob", "bob.bsky.social", "Bob", null, false),
            "2026-06-04T11:45:00.000Z");

        var display = PostDisplay.From(new FeedViewPost(Post(), reason, null));

        Assert.Equal("Bob がリポスト", display.ContextLabel);
    }

    [Fact]
    public void MapsFacetsIntoBodySegments()
    {
        var text = "see https://example.com #swift";
        var facets = new[]
        {
            new Facet(4, 23, [new FacetFeature.Link("https://example.com")]),
            new Facet(24, 30, [new FacetFeature.Tag("swift")]),
        };

        var display = Feed(Post(text: text, facets: facets));

        Assert.Equal(text, display.Body);
        Assert.Equal(
            [RichTextSegmentKind.Text, RichTextSegmentKind.Link, RichTextSegmentKind.Text, RichTextSegmentKind.Tag],
            display.Segments.Select(s => s.Kind));
        Assert.Equal(new Uri("https://example.com"), display.Segments[1].Url);
        Assert.Equal("#swift", display.Segments[3].Text);
    }

    [Fact]
    public void BodySegmentsFallBackToPlainTextWhenNoFacets()
    {
        var segment = Assert.Single(Feed(Post(text: "plain body")).Segments);

        Assert.Equal(new RichTextSegment(RichTextSegmentKind.Text, "plain body", null), segment);
    }

    [Fact]
    public void MapsVideoEmbedToPostVideo()
    {
        var video = new EmbedVideo(
            "https://video.example/playlist.m3u8",
            "https://video.example/poster.jpg",
            "a dog",
            new ImageAspectRatio(1280, 720));

        var display = Feed(Post(text: "watch this", embed: Embed(video: video)));

        Assert.NotNull(display.Video);
        Assert.Equal(new Uri("https://video.example/poster.jpg"), display.Video.ThumbUrl);
        Assert.Equal(new Uri("https://video.example/playlist.m3u8"), display.Video.PlaylistUrl);
        Assert.Equal("a dog", display.Video.Alt);
        Assert.Equal(1280.0 / 720.0, display.Video.AspectRatio);
    }

    [Fact]
    public void MapsRecordEmbedToQuotedPost()
    {
        var quoted = new EmbedRecord(
            "at://did:plc:quoted/app.bsky.feed.post/qqq",
            "bafyquoted",
            new ProfileViewBasic("did:plc:quoted", "quoted.bsky.social", "Quoted Author", "https://cdn.example/quoted.jpg", false),
            new PostRecord("the quoted text", "2026-06-10T08:00:00.000Z", []),
            [Embed(images: [new EmbedImage("https://cdn.example/q-thumb.jpg", "https://cdn.example/q-full.jpg", "pic", null)])]);

        var quote = Feed(Post(text: "check this out", embed: Embed(record: quoted))).Quote;

        Assert.NotNull(quote);
        Assert.Equal("at://did:plc:quoted/app.bsky.feed.post/qqq", quote.Id);
        Assert.Equal("bafyquoted", quote.Cid);
        Assert.Equal("Quoted Author", quote.AuthorDisplayName);
        Assert.Equal("quoted.bsky.social", quote.AuthorHandle);
        Assert.Equal(new Uri("https://cdn.example/quoted.jpg"), quote.AvatarUrl);
        Assert.Equal("the quoted text", quote.Body);
        Assert.Equal(new DateTimeOffset(2026, 6, 10, 8, 0, 0, TimeSpan.Zero), quote.CreatedAt);
        Assert.Equal(new Uri("https://cdn.example/q-thumb.jpg"), Assert.Single(quote.Images).ThumbUrl);
    }

    [Fact]
    public void QuoteAndVideoAreAbsentWithoutMatchingEmbeds()
    {
        var display = Feed(Post());

        Assert.Null(display.Quote);
        Assert.Null(display.Video);
    }

    [Fact]
    public void ParsesFractionalAndWholeSecondTimestamps()
    {
        var expected = new DateTimeOffset(2026, 6, 4, 12, 0, 0, TimeSpan.Zero);

        Assert.Equal(expected, Feed(Post(createdAt: "2026-06-04T12:00:00.000Z")).CreatedAt);
        Assert.Equal(expected, Feed(Post(createdAt: "2026-06-04T12:00:00Z")).CreatedAt);
    }

    [Fact]
    public void AnUnparseableTimestampFallsBackToTheEpoch()
    {
        Assert.Equal(DateTimeOffset.UnixEpoch, Feed(Post(createdAt: "yesterday")).CreatedAt);
    }
}
