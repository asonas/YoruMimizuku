import Foundation
import BlueskyCore

/// A failed content load, classified into a user-facing category with a friendly
/// title and message. Built from any thrown `Error` so view models can store it in
/// their failed state and views can show a tailored message (and pick an icon)
/// instead of dumping a raw Swift error description. `detail` keeps the raw
/// description for a secondary debug line.
public struct LoadFailure: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// No usable network connection (URLSession connectivity errors).
        case offline
        /// The server asked us to slow down (HTTP 429).
        case rateLimited
        /// The server failed (HTTP 5xx).
        case server
        /// Anything else (decoding, 4xx other than 429, unexpected).
        case unknown
    }

    public let kind: Kind
    /// The raw `String(describing:)` of the underlying error, for a small debug line.
    public let detail: String

    public init(_ error: Error) {
        self.detail = String(describing: error)
        self.kind = Self.classify(error)
    }

    private static func classify(_ error: Error) -> Kind {
        if let urlError = error as? URLError, Self.offlineCodes.contains(urlError.code) {
            return .offline
        }
        if case let XRPCError.requestFailed(status, _) = error {
            if status == 429 { return .rateLimited }
            if (500..<600).contains(status) { return .server }
        }
        return .unknown
    }

    /// URLSession error codes that mean "we couldn't reach the network", as opposed
    /// to a server that answered with an error.
    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
        .cannotFindHost, .timedOut, .dnsLookupFailed, .dataNotAllowed,
        .internationalRoamingOff,
    ]

    /// A short headline for the error screen.
    public var title: String {
        switch kind {
        case .offline: return "オフラインのようです"
        case .rateLimited: return "リクエストが多すぎます"
        case .server: return "サーバーエラー"
        case .unknown: return "読み込みに失敗しました"
        }
    }

    /// A one-line explanation with a hint at what to do next.
    public var message: String {
        switch kind {
        case .offline: return "インターネット接続を確認して、もう一度お試しください。"
        case .rateLimited: return "しばらく時間をおいてから再試行してください。"
        case .server: return "サーバー側で問題が発生しました。時間をおいて再試行してください。"
        case .unknown: return "通信中に問題が発生しました。再試行してください。"
        }
    }
}
