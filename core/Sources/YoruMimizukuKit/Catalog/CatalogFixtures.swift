import Foundation

/// Deterministic display models for the design catalog and snapshot tests.
/// Everything is pinned: the clock, IDs, text, and image URLs (bundled PNGs),
/// so the same variant renders identically on every run and platform.
public enum CatalogFixtures {
    /// Frozen "current time"; createdAt offsets render stable relative stamps.
    public static let now = Date(timeIntervalSince1970: 1_751_500_000)

    public static func imageURL(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "png")!
    }

    private static func image(_ name: String, w: Double, h: Double, alt: String = "") -> PostImage {
        let url = imageURL(name)
        return PostImage(thumbURL: url, fullsizeURL: url, alt: alt, aspectRatio: w / h)
    }

    public static func linkCard() -> LinkCard {
        LinkCard(url: URL(string: "https://example.com/article")!,
                 title: "サンプル記事のタイトル",
                 description: "OGP カードの見本。実在しない URL です。",
                 thumbURL: imageURL("sample-wide"))
    }

    public static func video() -> PostVideo {
        PostVideo(thumbURL: imageURL("sample-wide2"), playlistURL: nil,
                  alt: "動画の見本", aspectRatio: 16.0 / 9.0)
    }

    public static func quote() -> QuotedPost {
        // QuotedPost is its own memberwise struct (PostDisplay.swift:73-84).
        QuotedPost(
            id: "at://did:plc:catalog/app.bsky.feed.post/quoted",
            cid: "",
            authorDisplayName: "引用元ユーザー",
            authorHandle: "quoted.example.com",
            avatarURL: nil,
            body: "引用される側の投稿本文。",
            createdAt: now.addingTimeInterval(-7200),
            images: [image("sample-wide", w: 728, h: 410)],
            video: nil)
    }

    public static func post(for variant: CatalogVariant) -> PostDisplay {
        let base: (String, String) = ("カタログ 見本", "catalog.example.com")
        switch variant {
        case .postRowStandard, .actionBar, .toast:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/standard",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "標準的な投稿の見本。適度な長さの本文が1〜2行入る。",
                createdAt: now.addingTimeInterval(-1440),
                replyCount: 2, repostCount: 5, likeCount: 24)
        case .postRowSingleTallImage:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/tall",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "縦長画像1枚（5:4 キャップで全体表示ヒントが出る）。",
                createdAt: now.addingTimeInterval(-3600),
                images: [image("sample-tall", w: 400, h: 640, alt: "縦長の見本画像")])
        case .postRowTwoImages:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/two",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "画像2枚グリッドの見本（2026-07-03 のオーバーラップ再発防止）。",
                createdAt: now.addingTimeInterval(-1440),
                images: [image("sample-wide", w: 728, h: 410),
                         image("sample-wide2", w: 960, h: 540)],
                repostCount: 3, likeCount: 25)
        case .postRowFourImages:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/four",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "画像4枚グリッドの見本。",
                createdAt: now.addingTimeInterval(-1440),
                // Distinct alt per tile: PostImage.id is url + "|" + alt, so the
                // reused sample-wide would otherwise collide with the first tile
                // and SwiftUI's ForEach would drop it ("undefined results"),
                // collapsing the grid to three tiles.
                images: [image("sample-wide", w: 728, h: 410, alt: "1枚目"),
                         image("sample-wide2", w: 960, h: 540, alt: "2枚目"),
                         image("sample-tall", w: 400, h: 640, alt: "3枚目"),
                         image("sample-wide", w: 728, h: 410, alt: "4枚目")])
        case .postRowQuote, .quoteCard:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/quote",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "引用ポストの見本。", createdAt: now.addingTimeInterval(-900),
                quote: quote())
        case .postRowVideoPoster, .videoPoster:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/video",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "動画ポスターの見本。", createdAt: now.addingTimeInterval(-600),
                video: video())
        case .postRowLinkCard, .linkCard:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/link",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "リンクカードの見本。", createdAt: now.addingTimeInterval(-300),
                linkCard: linkCard())
        case .postRowSensitive:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/sensitive",
                authorDisplayName: base.0, authorHandle: base.1,
                body: "センシティブメディアぼかしの見本。",
                createdAt: now.addingTimeInterval(-120),
                mediaWarning: .adult,
                images: [image("sample-wide2", w: 960, h: 540)])
        case .postRowLongBody:
            return PostDisplay(
                id: "at://did:plc:catalog/app.bsky.feed.post/long",
                authorDisplayName: base.0, authorHandle: base.1,
                body: String(repeating: "長文の折返しと行間を確認するための本文。", count: 8),
                createdAt: now.addingTimeInterval(-60))
        }
    }
}
