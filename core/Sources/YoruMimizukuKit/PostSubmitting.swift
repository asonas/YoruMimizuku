/// Submits a composed post. The app wires a live implementation backed by
/// `PostService`; tests inject a fake. Abstracting the side effect keeps
/// `ComposerViewModel` free of networking and Apple-framework dependencies.
public protocol PostSubmitting: Sendable {
    func submit(_ draft: PostDraft) async throws -> PostResult
}
