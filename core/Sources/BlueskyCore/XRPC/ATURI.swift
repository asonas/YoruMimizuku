import Foundation

/// Helpers for AT-URIs (`at://<authority>/<collection>/<rkey>`).
public enum ATURI {
    /// The record key (last path segment) of an AT-URI, or nil when the string is
    /// not a `at://authority/collection/rkey` triple. Used to address a like /
    /// repost record for deletion.
    public static func rkey(_ uri: String) -> String? {
        guard uri.hasPrefix("at://") else { return nil }
        let parts = uri.dropFirst("at://".count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[2].isEmpty else { return nil }
        return String(parts[2])
    }

    /// The authority (repo DID/handle) of an AT-URI, or nil when the string is not a
    /// `at://authority/collection/rkey` triple. Used to address the author of a post.
    public static func repo(_ uri: String) -> String? {
        guard uri.hasPrefix("at://") else { return nil }
        let parts = uri.dropFirst("at://".count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty else { return nil }
        return String(parts[0])
    }
}
