import Foundation

/// One transient message shown to the user (e.g. "リンクをコピーしました"). The
/// `id` is a monotonic token so SwiftUI transitions treat each toast as distinct
/// and the auto-dismiss task can tell whether it still owns the current message.
public struct ToastMessage: Identifiable, Equatable, Sendable {
    public let id: Int
    public let text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

/// Holds the single transient toast the window overlays. `show` replaces any
/// visible toast and schedules its removal after `autoDismiss`; a newer `show`
/// supersedes the previous one so rapid copies just swap the text.
@MainActor
public final class ToastCenter: ObservableObject {
    @Published public private(set) var current: ToastMessage?

    private var lastToken = 0
    private let autoDismiss: Duration

    public init(autoDismiss: Duration = .milliseconds(1800)) {
        self.autoDismiss = autoDismiss
    }

    public func show(_ text: String) {
        lastToken += 1
        let token = lastToken
        current = ToastMessage(id: token, text: text)
        Task { [weak self, autoDismiss] in
            try? await Task.sleep(for: autoDismiss)
            self?.expire(token: token)
        }
    }

    public func dismiss() {
        current = nil
    }

    /// Clear the toast only if `token` still identifies the visible message; a
    /// stale token (a newer `show` already replaced it) is ignored.
    func expire(token: Int) {
        guard current?.id == token else { return }
        current = nil
    }
}
