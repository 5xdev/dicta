import AppKit
import Combine
import Sparkle

/// Wraps Sparkle. Scheduled checks surface as `availableUpdate` (the popover card + menu-bar dot) instead of a
/// dialog; the download → verify → install → relaunch step runs through Sparkle's standard UI.
///
/// Feed, public key and check interval come from Info.plist (`SU*` keys in project.yml). `DICTA_FEED_URL` in the
/// environment overrides the feed for local rehearsals.
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    /// The newest update Sparkle found in the current session, until the user acts on it or the session ends.
    @Published private(set) var availableUpdate: SUAppcastItem?
    /// False before the updater starts and while an update session is in progress.
    @Published private(set) var canCheckForUpdates = false
    /// Mirrors Sparkle's own UserDefaults-backed setting.
    @Published var automaticallyChecksForUpdates = true {
        didSet {
            guard isEnabled, updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// Debug builds only talk to a feed when `DICTA_FEED_URL` is set, so a stray `make run` never hits GitHub
    /// and never touches the Sparkle preferences it shares (same bundle ID) with the installed release build.
    let isEnabled: Bool

    private var controller: SPUStandardUpdaterController!
    private var updater: SPUUpdater { controller.updater }

    override init() {
        #if DEBUG
        isEnabled = Self.feedURLOverride != nil
        #else
        isEnabled = true
        #endif
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    /// Starts the update cycle. Sparkle wants this on the main thread once the app has finished launching.
    func start() {
        guard isEnabled else {
            Log.updates.info("updater disabled (Debug build without DICTA_FEED_URL)")
            return
        }
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        controller.startUpdater()
        Log.updates.info("updater started; feed=\(self.updater.feedURL?.absoluteString ?? "none", privacy: .public) automatic=\(self.automaticallyChecksForUpdates)")
    }

    /// "0.1.0 (1)" — marketing version + build number, for About.
    var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    /// Runs a check with Sparkle's own UI in immediate focus. From Settings → About that means "up to date" and
    /// errors are shown; from the popover card it lands straight on the Install sheet for the update already found.
    func checkForUpdates() {
        guard isEnabled else { return }
        // Sparkle activates LSUIElement apps itself, but do it first so the sheet lands in front of the popover.
        NSApp.activate(ignoringOtherApps: true)
        updater.checkForUpdates()
    }

    nonisolated private static var feedURLOverride: String? {
        guard let url = ProcessInfo.processInfo.environment["DICTA_FEED_URL"], !url.isEmpty else { return nil }
        return url
    }
}

// Sparkle calls both delegates on the main thread (SPUUpdater and SPUStandardUserDriver are main-thread objects),
// so the `nonisolated` requirements hop back onto the main actor with `assumeIsolated`.

extension UpdateManager: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        Self.feedURLOverride   // nil → SUFeedURL from Info.plist
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Log.updates.info("found update \(item.displayVersionString, privacy: .public) (\(item.versionString, privacy: .public))")
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Log.updates.info("no update: \(error.localizedDescription, privacy: .public)")
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Log.updates.error("update aborted: \(error.localizedDescription, privacy: .public)")
    }
}

extension UpdateManager: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false   // scheduled checks never pop a window; the popover card is the reminder
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated {
            Log.updates.info("showing update \(update.displayVersionString, privacy: .public); sparkleUI=\(handleShowingUpdate) userInitiated=\(state.userInitiated)")
            availableUpdate = update
        }
    }

    // The card stays up until the session ends (not on first user attention): the user may still dismiss
    // Sparkle's sheet with "Remind Me Later".
    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            Log.updates.info("update session finished")
            availableUpdate = nil
        }
    }
}
