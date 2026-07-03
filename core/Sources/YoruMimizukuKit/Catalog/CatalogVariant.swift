import Foundation

public enum CatalogPlatform: Sendable { case macOS, iPadOS }

/// The single source of truth for which design-catalog samples exist. App-side
/// registries map each case to a real view; a coverage test per app asserts no
/// declared variant is missing. IDs are the names used in design discussions.
public enum CatalogVariant: String, CaseIterable, Identifiable, Sendable {
    case postRowStandard, postRowSingleTallImage, postRowTwoImages
    case postRowFourImages, postRowQuote, postRowVideoPoster
    case postRowLinkCard, postRowSensitive, postRowLongBody
    case actionBar, quoteCard, linkCard, videoPoster, toast

    public var componentName: String {
        switch self {
        case .actionBar: "ActionBar"
        case .quoteCard: "QuoteCard"
        case .linkCard: "LinkCard"
        case .videoPoster: "VideoPoster"
        case .toast: "Toast"
        default: "PostRow"
        }
    }

    public var variantName: String {
        switch self {
        case .postRowStandard: "standard"
        case .postRowSingleTallImage: "single-tall-image"
        case .postRowTwoImages: "two-images"
        case .postRowFourImages: "four-images"
        case .postRowQuote: "quote"
        case .postRowVideoPoster: "video-poster"
        case .postRowLinkCard: "link-card"
        case .postRowSensitive: "sensitive"
        case .postRowLongBody: "long-body"
        case .actionBar, .quoteCard, .linkCard, .videoPoster, .toast: "default"
        }
    }

    public var id: String { "\(componentName)/\(variantName)" }

    public var platforms: Set<CatalogPlatform> {
        self == .toast ? [.macOS] : [.macOS, .iPadOS]
    }

    /// DesignMetrics identifiers this sample exercises — shown as the gallery caption.
    public var metricsUsed: [String] {
        switch self {
        case .postRowTwoImages, .postRowFourImages:
            ["gridGutter", "gridTileHeight", "thumbnailCornerRadius", "mediaTopGap"]
        case .postRowStandard, .postRowLongBody:
            ["bodyStackSpacing", "actionBarTopGap", "actionBarItemSpacing"]
        case .postRowSingleTallImage, .postRowSensitive:
            ["mediaTopGap", "mediaMaxWidth", "thumbnailCornerRadius"]
        case .actionBar: ["actionBarTopGap", "actionBarItemSpacing"]
        case .postRowQuote, .quoteCard: ["mediaTopGap", "thumbnailCornerRadius"]
        case .postRowVideoPoster, .videoPoster, .postRowLinkCard, .linkCard:
            ["mediaTopGap", "mediaMaxWidth", "thumbnailCornerRadius"]
        case .toast: []
        }
    }
}
