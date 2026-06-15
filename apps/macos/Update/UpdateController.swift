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

    /// Armed by the launch check so the next update Sparkle surfaces appears as a
    /// foreground dialog instead of the quiet gentle-reminder badge.
    private var launchPrompt = LaunchUpdatePrompt()

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

    /// Quietly asks Sparkle to fetch the feed at launch. Nothing is shown when
    /// the user is already up to date (no "you're up to date" dialog to nag on
    /// every open); when a newer build is published the armed `launchPrompt`
    /// turns the find into the standard update dialog. Honors the "起動時に自動で
    /// 確認" toggle so the user can opt out.
    func checkForUpdatesOnLaunch() {
        guard sparkleConfigured else { return }
        guard updaterController.updater.automaticallyChecksForUpdates else { return }
        launchPrompt.arm()
        updaterController.updater.checkForUpdatesInBackground()
    }
}

extension UpdateController: @MainActor SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        channel.feedURL.absoluteString
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        // If the launch check found nothing, the user-driver delegate never ran
        // and the latch is still armed. Clear it here so a later periodic check
        // falls back to the gentle badge instead of popping a dialog.
        _ = launchPrompt.consume()
    }
}

extension UpdateController: @MainActor SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        if immediateFocus { return true }
        // A launch-triggered find is shown as a dialog; periodic finds stay gentle.
        if launchPrompt.consume() { return true }
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
