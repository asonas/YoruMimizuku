#if DEBUG
import SwiftUI
import YoruMimizukuKit

/// Maps every CatalogVariant to the real macOS view rendering its fixture.
/// The gallery and (eventually) a snapshot test iterate this same table.
@MainActor
enum CatalogRegistry {
    static func view(for variant: CatalogVariant) -> AnyView? {
        guard variant.platforms.contains(.macOS) else { return nil }
        let now = CatalogFixtures.now
        switch variant {
        case .actionBar:
            // The action bar is a PostRow slot, so show a standard row focused on it.
            return AnyView(PostRowView(post: CatalogFixtures.post(for: .actionBar), density: .comfortable, now: now))
        case .quoteCard:
            return AnyView(QuoteCardView(quote: CatalogFixtures.quote(), density: .comfortable, now: now))
        case .linkCard:
            return AnyView(LinkCardView(card: CatalogFixtures.linkCard(), density: .comfortable))
        case .videoPoster:
            return AnyView(VideoPosterView(video: CatalogFixtures.video(), maxWidth: 440))
        case .toast:
            return AnyView(ToastView(message: ToastMessage(id: 0, text: "リンクをコピーしました")))
        default:
            return AnyView(PostRowView(post: CatalogFixtures.post(for: variant), density: .comfortable, now: now))
        }
    }
}
#endif
