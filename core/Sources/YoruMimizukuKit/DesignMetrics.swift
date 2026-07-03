import Foundation

/// Named layout metrics shared by every platform UI. These are the vocabulary
/// used in design discussions ("PostRow の actionBarTopGap を 6→8 に"): the
/// identifier in conversation IS the identifier in code. Values are documented
/// where they apply; changing one here changes every platform.
public enum DesignMetrics {
    /// Gap between the post body/media block and the action bar (PostRow).
    public static let actionBarTopGap: Double = 6
    /// Horizontal spacing between reply / repost / like / link actions.
    public static let actionBarItemSpacing: Double = 26
    /// Gap above inline media, link cards, and quote cards (PostRow).
    public static let mediaTopGap: Double = 3
    /// Gutter between tiles in the 2+ image grid (PostRow imageGrid).
    public static let gridGutter: Double = 5
    /// Fixed tile height in the 2+ image grid.
    public static let gridTileHeight: Double = 140
    /// Corner radius of thumbnails, posters, and media curtains.
    public static let thumbnailCornerRadius: Double = 10

    /// Vertical spacing of the author/body/media/actions stack, by density.
    public static func bodyStackSpacing(_ density: DisplayDensity) -> Double {
        density == .compact ? 2 : 4
    }

    /// Maximum media width in the vertical (non-reflow) layout, by density.
    public static func mediaMaxWidth(_ density: DisplayDensity) -> Double {
        density == .compact ? 320 : 440
    }
}
