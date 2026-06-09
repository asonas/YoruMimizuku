import Foundation

struct UpdateBadgeState: Equatable {
    private(set) var updateAvailable: Bool

    init(updateAvailable: Bool = false) {
        self.updateAvailable = updateAvailable
    }

    mutating func scheduledUpdateFound() {
        updateAvailable = true
    }

    mutating func updateSessionFinished() {
        updateAvailable = false
    }

    static func versionDisplay(shortVersion: String?, build: String?) -> String {
        let version = shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let build = build?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        case (.none, let .some(build)):
            return build
        case (.none, .none):
            return "Unknown"
        }
    }
}
