import Foundation

/// Signals that the current account's OAuth session can no longer be refreshed
/// (a dead/expired refresh token — `invalid_grant`). Retrying is futile in that
/// state, so the app should drop the account and return to the login screen.
public enum SessionExpiry {
    /// Posted (no object) when an irrecoverable refresh failure is observed.
    public static let notification = Notification.Name("yoru.sessionExpired")

    /// Posts `notification` and returns true when `error` is an irrecoverable OAuth
    /// refresh failure; otherwise returns false. Safe to call from any error path.
    @discardableResult
    public static func reportIfExpired(_ error: Error) -> Bool {
        guard let oauth = error as? OAuthError,
              case .tokenRequestFailed(_, "invalid_grant", _) = oauth else {
            return false
        }
        NotificationCenter.default.post(name: notification, object: nil)
        return true
    }
}
