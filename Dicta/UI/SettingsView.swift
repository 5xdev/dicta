import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gear") }
            SarvamSettings()
                .tabItem { Label("Sarvam AI", systemImage: "cloud") }
            PermissionsSettings()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 420)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var microphone: MicrophoneSelection

    var body: some View {
        Form {
            Section("Push to talk") {
                Picker("Hotkey", selection: $preferences.hotkey) {
                    ForEach(Hotkey.allCases) { Text($0.title).tag($0) }
                }
                if preferences.hotkey == .fn {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Set **Press 🌐 key to → Do Nothing** in Keyboard settings so Fn doesn't open the emoji picker.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open Keyboard Settings…") { Permissions.openKeyboardSettings() }
                            .controlSize(.small)
                    }
                }
            }

            Section("Microphone") {
                Picker("Input device", selection: $microphone.deviceUID) {
                    Text(systemDefaultLabel).tag(MicrophoneSelection.systemDefaultUID)
                    if !microphone.devices.isEmpty { Divider() }
                    ForEach(microphone.devices) { Text($0.name).tag($0.uid) }
                    if microphone.isUnavailable {
                        Text("\(microphone.deviceName ?? "Selected microphone") (not connected)")
                            .tag(microphone.deviceUID)
                    }
                }
                if microphone.isUnavailable {
                    Label("That microphone isn't connected — the system default will be used until it's plugged back in.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("Dicta always records from this microphone, even if macOS switches its default input.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Launch at login", isOn: $preferences.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .onAppear { microphone.refresh() }
    }

    private var systemDefaultLabel: String {
        if let name = microphone.systemDefaultName { return "System default (\(name))" }
        return "System default"
    }
}

private struct SarvamSettings: View {
    @EnvironmentObject private var preferences: Preferences
    @State private var revealKey = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Group {
                        if revealKey {
                            TextField("API key", text: $preferences.sarvamAPIKey)
                        } else {
                            SecureField("API key", text: $preferences.sarvamAPIKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    Button {
                        revealKey.toggle()
                    } label: {
                        Image(systemName: revealKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(revealKey ? "Hide key" : "Show key")
                }
                HStack(spacing: 6) {
                    Image(systemName: preferences.hasAPIKey ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(preferences.hasAPIKey ? .green : .orange)
                    Text(preferences.hasAPIKey ? "Stored securely in your Keychain." : "Required. Get a key from the Sarvam dashboard.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link("indus.sarvam.ai", destination: URL(string: "https://indus.sarvam.ai")!)
                }
                .font(.caption)
            } header: {
                Text("API key")
            }

            Section("Model") {
                Picker("Model", selection: $preferences.sarvamModel) {
                    ForEach(SarvamModel.allCases) { Text($0.title).tag($0) }
                }
                Picker("Language", selection: $preferences.sarvamLanguage) {
                    ForEach(SarvamLanguage.all) { Text($0.name).tag($0.code) }
                }
                Picker("Mode", selection: $preferences.sarvamMode) {
                    ForEach(SarvamMode.allCases) { Text($0.title).tag($0) }
                }
                Text("Audio is sent to api.sarvam.ai as 16 kHz mono WAV when you release the hotkey. Recordings stop automatically at \(Int(SarvamTranscriber.maxUtteranceSeconds)) s — the REST endpoint is built for short clips.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsSettings: View {
    @EnvironmentObject private var permissions: PermissionsMonitor

    var body: some View {
        Form {
            row(
                title: "Microphone",
                detail: "Capture audio while the hotkey is held.",
                granted: permissions.micAuthorized,
                action: Permissions.openMicrophoneSettings
            )
            row(
                title: "Accessibility",
                detail: "Listen for the global hotkey and type text into the active app.",
                granted: permissions.accessibilityTrusted,
                action: permissions.requestAccessibility
            )
        }
        .formStyle(.grouped)
        .onAppear { permissions.refresh() }
    }

    private func row(title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Open Settings…", action: action)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AboutSettings: View {
    @EnvironmentObject private var updates: UpdateManager

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Dicta").font(.title2.bold())
            Text("Push-to-talk dictation for macOS, powered by Sarvam AI.")
                .foregroundStyle(.secondary)
            Text("Version \(updates.currentVersion)")
                .font(.caption).foregroundStyle(.tertiary)

            if updates.isEnabled {
                VStack(spacing: 10) {
                    Button("Check for Updates…") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                    Toggle("Check for updates automatically", isOn: $updates.automaticallyChecksForUpdates)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                }
                .padding(.top, 12)
            } else {
                Text("Updates are disabled in Debug builds (set DICTA_FEED_URL to test them).")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.top, 12)
            }

            Link("Release notes", destination: URL(string: "https://github.com/5xdev/dicta/releases")!)
                .font(.caption)
                .padding(.top, 4)
        }
        .padding(32)
    }
}
