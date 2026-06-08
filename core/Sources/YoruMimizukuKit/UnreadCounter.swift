/// Computes how many items are newer than the last item the viewer saw.
///
/// `ids` are ordered newest-first (the list head is the freshest item). The
/// `marker` is the id of the item that was at the head the last time the tab was
/// seen. The number of ids above the marker is the unread count.
public enum UnreadCounter {
    /// - Returns: 0 when there is no marker yet or the marker is still at the head;
    ///   the index of the marker (how many fresher items sit above it); or the full
    ///   count when the marker has scrolled out of the loaded window.
    public static func unread(ids: [String], since marker: String?) -> Int {
        guard let marker else { return 0 }
        guard let index = ids.firstIndex(of: marker) else { return ids.count }
        return index
    }
}
