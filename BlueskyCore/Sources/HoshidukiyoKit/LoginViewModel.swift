import Foundation

/// Drives the login screen: holds the handle input and the login state machine.
/// `@MainActor` because it is bound to SwiftUI; the actual network/browser work
/// happens inside the injected `LoginPerforming`.
@MainActor
public final class LoginViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case authenticating
        case failed(String)
        case authenticated(did: String)
    }

    @Published public var handle: String = ""
    @Published public private(set) var state: State = .idle

    private let performer: LoginPerforming

    public init(performer: LoginPerforming) {
        self.performer = performer
    }

    private var trimmedHandle: String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when there is a non-blank handle and no login is in flight.
    public var canSubmit: Bool {
        !trimmedHandle.isEmpty && state != .authenticating
    }

    /// Run the login. No-op when the handle is blank or a login is already running.
    public func submit() async {
        let account = trimmedHandle
        guard !account.isEmpty, state != .authenticating else { return }
        state = .authenticating
        do {
            let did = try await performer.login(handle: account)
            state = .authenticated(did: did)
        } catch {
            state = .failed(String(describing: error))
        }
    }
}
