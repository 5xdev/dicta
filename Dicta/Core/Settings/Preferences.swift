import Combine
import Foundation
import ServiceManagement

/// The user's settings, as one observable object the Settings window binds to.
///
/// Plain values live in UserDefaults; the Sarvam API key lives in the Keychain. The microphone choice is its own
/// object (`microphone`) because it carries live state — the list of connected devices — as well as a persisted
/// value. What "no saved setting yet" means is decided in `init` here and nowhere else.
@MainActor
final class Preferences: ObservableObject {
    private enum Keys {
        static let hotkey = "hotkey"
        static let sarvamModel = "sarvam.model"
        static let sarvamLanguage = "sarvam.language"
        static let sarvamMode = "sarvam.mode"
        static let apiKeyAccount = "sarvam-api-key"
    }

    // MARK: Push to talk

    @Published var hotkey: Hotkey {
        didSet { UserDefaults.standard.set(hotkey.rawValue, forKey: Keys.hotkey) }
    }

    /// Which microphone to record from (Settings → General → Microphone).
    let microphone = MicrophoneSelection()

    // MARK: Sarvam AI

    /// Bound directly to the Settings text field, so this changes on every keystroke; the Keychain write is
    /// debounced (see `scheduleAPIKeySave`) and flushed on quit rather than hitting SecItemUpdate per character.
    @Published var sarvamAPIKey: String {
        didSet { scheduleAPIKeySave() }
    }
    @Published var sarvamModel: SarvamModel {
        didSet { UserDefaults.standard.set(sarvamModel.rawValue, forKey: Keys.sarvamModel) }
    }
    @Published var sarvamLanguage: String {
        didSet { UserDefaults.standard.set(sarvamLanguage, forKey: Keys.sarvamLanguage) }
    }
    @Published var sarvamMode: SarvamMode {
        didSet { UserDefaults.standard.set(sarvamMode.rawValue, forKey: Keys.sarvamMode) }
    }

    var hasAPIKey: Bool { !trimmedAPIKey.isEmpty }
    private var trimmedAPIKey: String { sarvamAPIKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Snapshot of the Sarvam settings for one utterance.
    var sarvamConfig: SarvamConfig {
        SarvamConfig(apiKey: trimmedAPIKey, model: sarvamModel, languageCode: sarvamLanguage, mode: sarvamMode)
    }

    // MARK: Launch at login

    /// Backed by `SMAppService` rather than stored: macOS owns this state (the user can change it in System Settings).
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                Log.app.error("Launch at login failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Lifecycle

    private var apiKeySave: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        hotkey = defaults.string(forKey: Keys.hotkey).flatMap(Hotkey.init(rawValue:)) ?? .fn

        // Keychain first; SARVAM_API_KEY env var is a convenience for local dev runs.
        sarvamAPIKey = Keychain.get(Keys.apiKeyAccount)
            ?? ProcessInfo.processInfo.environment["SARVAM_API_KEY"]
            ?? ""
        sarvamModel = defaults.string(forKey: Keys.sarvamModel).flatMap(SarvamModel.init(rawValue:)) ?? .saarasV4
        sarvamLanguage = defaults.string(forKey: Keys.sarvamLanguage) ?? SarvamLanguage.autoDetect.code
        sarvamMode = defaults.string(forKey: Keys.sarvamMode).flatMap(SarvamMode.init(rawValue:)) ?? .transcribe
    }

    /// Writes any pending (debounced) API-key change now. Called on quit so a keystroke-fresh edit isn't lost.
    func flush() {
        persistAPIKey()
    }

    private func scheduleAPIKeySave() {
        apiKeySave?.cancel()
        apiKeySave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persistAPIKey()
        }
    }

    private func persistAPIKey() {
        apiKeySave?.cancel()
        apiKeySave = nil
        Keychain.set(trimmedAPIKey, for: Keys.apiKeyAccount)
    }
}
