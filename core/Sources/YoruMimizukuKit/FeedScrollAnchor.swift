/// Picks the anchor row for preserving a feed's scroll position across a tab
/// switch: the top-most row currently on screen.
///
/// `order` is the feed's display order (top-first, as arranged for rendering).
/// `visible` is the set of row ids currently laid out on screen, gathered from
/// each row's appear/disappear. The anchor is the first id in display order that
/// is still visible, so restoring to it puts the same row back at the top.
public enum FeedScrollAnchor {
    /// - Returns: the top-most visible id in display order, or nil when nothing is
    ///   visible (an empty feed, or before any row has appeared).
    public static func topVisibleID(order: [String], visible: Set<String>) -> String? {
        order.first { visible.contains($0) }
    }
}
