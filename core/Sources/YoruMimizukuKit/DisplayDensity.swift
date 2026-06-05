/// How densely a post row is rendered. `compact` is the Yorufukurou-style tight
/// layout; `comfortable` adds avatars, thumbnails and action counts. Default is
/// `comfortable`.
public enum DisplayDensity: String, CaseIterable, Sendable {
    case compact
    case comfortable

    public static let `default`: DisplayDensity = .comfortable
}
