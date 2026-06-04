import SwiftUI
import HoshidukiyoKit

/// Minimal root used to prove the app builds and links HoshidukiyoKit.
/// Replaced by `MainWindowView` in the next task.
struct ContentView: View {
    private let posts = PostDisplay.samples(now: Date())

    var body: some View {
        List(posts) { post in
            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorDisplayName).font(.headline)
                Text(post.body).font(.body)
            }
        }
        .frame(minWidth: 360, minHeight: 480)
    }
}
