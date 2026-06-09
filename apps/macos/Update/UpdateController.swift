import Foundation
import Sparkle

@MainActor
final class UpdateController: NSObject, ObservableObject {
    @Published private(set) var updateAvailable = false
    @Published private(set) var canCheckForUpdates = false
    @Published var channel: UpdateChannel {
        didSet { channelStore.channel = channel }
    }

    private var badgeState = UpdateBadgeState() {
        didSet { updateAvailable = badgeState.updateAvailable }
    }

    private let channelStore: UpdateChannelStore
    private let sparkleConfigured: Bool
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: self
    )

    override convenience init() {
        self.init(channelStore: UpdateChannelStore())
    }

    init(channelStore: UpdateChannelStore) {
        self.channelStore = channelStore
        self.channel = channelStore.channel
        let publicKey = Bundle.main.infoDictionary?["SUPublicEDKey"] as? String
        self.sparkleConfigured = publicKey?.hasPrefix("__REPLACE_WITH_") == false
        super.init()
        if sparkleConfigured {
            updaterController.updater.clearFeedURLFromUserDefaults()
            canCheckForUpdates = updaterController.updater.canCheckForUpdates
        } else {
            canCheckForUpdates = false
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { sparkleConfigured && updaterController.updater.automaticallyChecksForUpdates }
        set {
            guard sparkleConfigured else { return }
            updaterController.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    func checkForUpdates() {
        guard sparkleConfigured else { return }
        updaterController.checkForUpdates(nil)
    }
}

extension UpdateController: @MainActor SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        channel.feedURL.absoluteString
    }
}

extension UpdateController: @MainActor SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        if immediateFocus { return true }
        badgeState.scheduledUpdateFound()
        return false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate {
            badgeState.scheduledUpdateFound()
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        badgeState.updateSessionFinished()
    }

    func standardUserDriverWillFinishUpdateSession() {
        badgeState.updateSessionFinished()
    }
}
