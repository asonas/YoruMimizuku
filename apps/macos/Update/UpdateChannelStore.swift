import Foundation

struct UpdateChannelStore {
    private static let key = "updates.channel"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var channel: UpdateChannel {
        get {
            guard let raw = defaults.string(forKey: Self.key),
                  let channel = UpdateChannel(rawValue: raw) else {
                return .stable
            }
            return channel
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.key)
        }
    }
}
