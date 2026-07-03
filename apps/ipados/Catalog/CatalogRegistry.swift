#if DEBUG
import SwiftUI
import YoruMimizukuKit

/// Maps every CatalogVariant to the real iPad view rendering its fixture.
/// Mirrors `apps/macos/Catalog/CatalogRegistry.swift`; the iPad `PostRowView`
/// is a separate implementation from the macOS one, so this registry threads
/// fixtures through the iPad inits directly rather than sharing code with macOS.
@MainActor
enum CatalogRegistry {
    static func view(for variant: CatalogVariant, density: DisplayDensity = .comfortable, width: CGFloat = 560) -> AnyView? {
        guard variant.platforms.contains(.iPadOS) else { return nil }
        let now = CatalogFixtures.now
        switch variant {
        case .actionBar:
            // The action bar is a PostRow slot, so show a standard row focused on it.
            return AnyView(PostRowView(post: CatalogFixtures.post(for: .actionBar), density: density, now: now, contentWidth: width))
        case .quoteCard:
            return AnyView(QuoteCardView(quote: CatalogFixtures.quote(), density: density, now: now))
        case .linkCard:
            return AnyView(LinkCardView(card: CatalogFixtures.linkCard(), density: density))
        case .videoPoster:
            return AnyView(VideoPosterView(video: CatalogFixtures.video(), maxWidth: 440))
        default:
            return AnyView(PostRowView(post: CatalogFixtures.post(for: variant), density: density, now: now, contentWidth: width))
        }
    }
}
#endif
