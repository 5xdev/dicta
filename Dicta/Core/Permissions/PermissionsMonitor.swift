import Combine
import Foundation

/// The two TCC grants Dicta needs, as published flags for the UI (permission cards) and the controller
/// (which installs the hotkey tap once Accessibility is trusted).
///
/// Accessibility can be granted while the app is running — System Settings, no relaunch — so after `start()` the
/// flags are re-read every 2 s. They only publish on change, otherwise every observing view would re-render each tick.
@MainActor
final class PermissionsMonitor: ObservableObject {
    @Published private(set) var micAuthorized = false
    @Published private(set) var accessibilityTrusted = false

    private var poll: Timer?

    /// Reads the current state, asks for the microphone, prompts for Accessibility if needed, then keeps polling.
    func start() {
        refresh()
        Task {
            let granted = await Permissions.requestMicrophone()
            if micAuthorized != granted { micAuthorized = granted }
            if !accessibilityTrusted { Permissions.promptAccessibility() }
            refresh()
        }
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        poll?.invalidate()
        poll = nil
    }

    func refresh() {
        let mic = Permissions.microphoneAuthorized
        let ax = Permissions.accessibilityTrusted
        if micAuthorized != mic { micAuthorized = mic }
        if accessibilityTrusted != ax { accessibilityTrusted = ax }
    }

    /// System prompt plus a deep link — the prompt alone is easy to dismiss and never shows a second time.
    func requestAccessibility() {
        Permissions.promptAccessibility()
        Permissions.openAccessibilitySettings()
    }
}
