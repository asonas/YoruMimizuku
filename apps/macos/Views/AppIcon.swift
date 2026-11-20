import SwiftUI
import AppKit

/// The app's icon set: the SVGs in `design/icons` (Lucide's icons, plus two
/// drawn here; see its README for origin and license), checked by
/// `mise run icons:lint`. They replace SF Symbols on macOS so the shapes can be
/// shared with Windows. Liked and reposted states are shown by color, not by a
/// filled variant.
enum AppIcon: String, CaseIterable, Sendable {
    case arrowUp = "arrow-up"
    case atSign = "at-sign"
    case badgeCheck = "badge-check"
    case bell = "bell"
    case bellOff = "bell-off"
    case check = "check"
    case chevronDown = "chevron-down"
    case chevronLeft = "chevron-left"
    case chevronRight = "chevron-right"
    case chevronUp = "chevron-up"
    case circleArrowDown = "circle-arrow-down"
    case circleMinus = "circle-minus"
    case circlePlay = "circle-play"
    case circleX = "circle-x"
    case cloudExclamationPoint = "cloud-exclamation-point"
    case cog = "cog"
    case compass = "compass"
    case expand = "expand"
    case eyeOff = "eye-off"
    case globe = "globe"
    case heart = "heart"
    case hourglass = "hourglass"
    case image = "image"
    case imagePlus = "image-plus"
    case info = "info"
    case link = "link"
    case list = "list"
    case listFilter = "list-filter"
    case logOut = "log-out"
    case messageCircle = "message-circle"
    case messageQuote = "message-quote"
    case moonStar = "moon-star"
    case palette = "palette"
    case play = "play"
    case pencil = "pencil"
    case plus = "plus"
    case quote = "quote"
    case `repeat` = "repeat"
    case reply = "reply"
    case rotateCw = "rotate-cw"
    case rows2 = "rows-2"
    case rss = "rss"
    case search = "search"
    case panelLeft = "panel-left"
    case squarePen = "square-pen"
    case trash = "trash"
    case triangleExclamationPoint = "triangle-exclamation-point"
    case type = "type"
    case userPlus = "user-plus"
    case users = "users"
    case videoPlus = "video-plus"
    case wifiOff = "wifi-off"
    case x = "x"
}

/// Loads the bundled SVGs once as template images, so they take the
/// foreground color like SF Symbols.
@MainActor
enum AppIconImages {
    private static var cache: [AppIcon: NSImage] = [:]
    private final class BundleToken {}

    static func image(_ icon: AppIcon) -> NSImage {
        if let cached = cache[icon] { return cached }
        let bundle = Bundle(for: BundleToken.self)
        let url = bundle.url(forResource: icon.rawValue, withExtension: "svg", subdirectory: "icons")
        let image = url.flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: 24, height: 24))
        image.isTemplate = true
        cache[icon] = image
        return image
    }

    /// A 16pt copy for places that size images themselves (menus, labels).
    static func menuImage(_ icon: AppIcon) -> NSImage {
        let copy = image(icon).copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        copy.isTemplate = true
        return copy
    }
}

extension Image {
    /// An app icon at 16pt, for menu items and `Label` icons.
    @MainActor
    static func icon(_ icon: AppIcon) -> Image {
        Image(nsImage: AppIconImages.menuImage(icon)).renderingMode(.template)
    }
}

/// An app icon drawn at `size` points, taking the foreground style. `size` is
/// the icon's whole 24-unit canvas; the drawing sits inside its 1-unit margin.
/// VoiceOver skips it unless it has a `label`, which an icon that carries
/// meaning on its own (a verified badge) needs; a button names itself instead.
struct Icon: View {
    let icon: AppIcon
    var size: CGFloat = 16
    var label: String?

    init(_ icon: AppIcon, size: CGFloat = 16, label: String? = nil) {
        self.icon = icon
        self.size = size
        self.label = label
    }

    var body: some View {
        Image(nsImage: AppIconImages.image(icon))
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityLabel(Text(label ?? ""))
            .accessibilityHidden(label == nil)
    }
}
