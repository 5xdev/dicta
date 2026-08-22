import AppKit

/// Composition root: builds the model objects once and wires the pipeline's lifecycle to the app's.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// User settings (UserDefaults + Keychain); shared with the Settings window.
    let preferences: Preferences
    /// Microphone / Accessibility grants; shared with the popover cards and Settings → Permissions.
    let permissions: PermissionsMonitor
    /// The dictation pipeline: hotkey → record → transcribe → insert.
    let controller: DictationController
    /// Sparkle wrapper; shared with the popover (update card) and Settings → About.
    let updates = UpdateManager()
    private var overlay: OverlayPanelController?

    override init() {
        let preferences = Preferences()
        let permissions = PermissionsMonitor()
        self.preferences = preferences
        self.permissions = permissions
        controller = DictationController(preferences: preferences, permissions: permissions)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayPanelController(controller: controller)
        controller.start()
        updates.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}
