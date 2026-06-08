import Foundation

/// A user's profile as the author tab header renders it. `displayName` and `bio`
/// are optional because the actor may not have set them; `bio` is currently always
/// nil from the basic profile view (see `LiveAuthorProfileLoader`).
public struct AuthorProfile: Equatable, Sendable {
    public let did: String
    public let handle: String
    public let displayName: String?
    public let avatarURL: URL?
    public let bio: String?

    public init(did: String, handle: String, displayName: String?, avatarURL: URL?, bio: String?) {
        self.did = did
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.bio = bio
    }
}

/// Resolves an actor's profile for the author tab header. The app provides the live
/// implementation (authenticated XRPC + mapping); tests inject a stub.
public protocol AuthorProfileLoading: Sendable {
    func loadProfile(actor: String) async throws -> AuthorProfile
}

/// Drives the author tab's profile header. Holds the loaded profile (or an initial
/// snapshot captured from the tapped avatar so the header renders before the fetch
/// completes). The header is cosmetic, so a failed load keeps any initial snapshot
/// and flips `failed` rather than surfacing an error screen.
@MainActor
public final class ProfileHeaderViewModel: ObservableObject {
    @Published public private(set) var profile: AuthorProfile?
    @Published public private(set) var failed = false

    private let loader: AuthorProfileLoading
    private let actor: String

    public init(loader: AuthorProfileLoading, actor: String, initial: AuthorProfile? = nil) {
        self.loader = loader
        self.actor = actor
        self.profile = initial
    }

    /// Fetch the full profile. On success replaces `profile`; on failure keeps the
    /// initial snapshot (if any) and sets `failed`.
    public func load() async {
        do {
            profile = try await loader.loadProfile(actor: actor)
            failed = false
        } catch {
            failed = true
        }
    }
}
