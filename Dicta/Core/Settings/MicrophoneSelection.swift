import Combine
import Foundation

/// Which microphone Dicta records from, plus the live list it is chosen from.
///
/// `deviceUID` is the persisted CoreAudio UID; `""` (`systemDefaultUID`) means follow the system default input.
/// The device's name is persisted alongside so the picker can still label the choice once the mic is unplugged.
/// `devices` and `systemDefaultName` are refreshed whenever CoreAudio reports a change.
@MainActor
final class MicrophoneSelection: ObservableObject {
    static let systemDefaultUID = ""

    private enum Keys {
        static let uid = "audio.inputDeviceUID"
        static let name = "audio.inputDeviceName"
    }

    @Published var deviceUID: String {
        didSet {
            let defaults = UserDefaults.standard
            if deviceUID.isEmpty {
                deviceName = nil
                defaults.removeObject(forKey: Keys.uid)
                defaults.removeObject(forKey: Keys.name)
            } else {
                defaults.set(deviceUID, forKey: Keys.uid)
                rememberDeviceName()
            }
        }
    }
    /// Last known name of the chosen device — survives it being unplugged.
    @Published private(set) var deviceName: String?

    /// Microphones currently connected, refreshed whenever CoreAudio reports a change.
    @Published private(set) var devices: [AudioInputDevice] = []
    /// Name of the system default input, shown alongside the "System default" option.
    @Published private(set) var systemDefaultName: String?

    /// `deviceUID` in the recorder's terms: `nil` follows the system default.
    var preferredDeviceUID: String? { deviceUID.isEmpty ? nil : deviceUID }

    /// True when a specific mic is chosen but isn't plugged in right now (capture falls back to the system default).
    var isUnavailable: Bool {
        !deviceUID.isEmpty && !devices.contains { $0.uid == deviceUID }
    }

    private var observer: AnyObject?

    init() {
        let defaults = UserDefaults.standard
        deviceUID = defaults.string(forKey: Keys.uid) ?? Self.systemDefaultUID
        deviceName = defaults.string(forKey: Keys.name)

        refresh()
        observer = AudioInputDevices.observeChanges { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Re-reads the connected devices and the system default. Only publishes what actually changed.
    func refresh() {
        let connected = AudioInputDevices.all()
        if devices != connected { devices = connected }
        let defaultName = AudioInputDevices.systemDefault()?.name
        if systemDefaultName != defaultName { systemDefaultName = defaultName }
        rememberDeviceName()   // picks up a rename while the device is connected
    }

    /// Persists the chosen microphone's current name so the picker can still label it once it's unplugged.
    /// No-op when the device isn't connected (the remembered name stays) or the name hasn't changed.
    private func rememberDeviceName() {
        guard let name = devices.first(where: { $0.uid == deviceUID })?.name, name != deviceName else { return }
        deviceName = name
        UserDefaults.standard.set(name, forKey: Keys.name)
    }
}
