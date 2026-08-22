import Sparkle
import SwiftUI

/// The status-bar icon. Reflects pipeline state at a glance.
struct MenuBarLabel: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var updates: UpdateManager

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .overlay(alignment: .topTrailing) {
                if updates.availableUpdate != nil {
                    Circle()
                        .fill(.tint)
                        .frame(width: 6, height: 6)
                        .offset(x: 2, y: -1)
                }
            }
    }

    private var symbol: String {
        switch controller.state {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .error: return "mic.slash"
        }
    }
}

/// Popover shown when clicking the status-bar icon.
struct MenuBarView: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var permissions: PermissionsMonitor
    @EnvironmentObject private var updates: UpdateManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !permissions.micAuthorized || !permissions.accessibilityTrusted || !preferences.hasAPIKey {
                permissionsCard
            }
            if let update = updates.availableUpdate {
                updateCard(update)
            }
            hintRow
            if let last = controller.lastTranscript {
                LastTranscriptCard(text: last)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Dicta").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                controller.toggle()
            } label: {
                Image(systemName: controller.state == .recording ? "stop.circle.fill" : "record.circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .help(controller.state == .recording ? "Stop recording" : "Start recording (hands-free)")
            .disabled(!permissions.micAuthorized)
        }
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !permissions.micAuthorized {
                permissionRow(
                    icon: "mic.slash.fill",
                    title: "Microphone access needed",
                    action: { Permissions.openMicrophoneSettings() }
                )
            }
            if !permissions.accessibilityTrusted {
                permissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility access needed",
                    subtitle: "For the global hotkey and typing text into apps.",
                    action: { permissions.requestAccessibility() }
                )
            }
            if !preferences.hasAPIKey {
                permissionRow(
                    icon: "key.fill",
                    title: "Sarvam AI API key needed",
                    subtitle: "Add it under Settings → Sarvam AI.",
                    action: showSettings
                )
            }
        }
        .padding(10)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func permissionRow(icon: String, title: String, subtitle: String? = nil, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.orange).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button("Grant", action: action).controlSize(.small)
        }
    }

    private func updateCard(_ update: SUAppcastItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dicta \(update.displayVersionString) is available").font(.callout.weight(.medium))
                if let notes = update.releaseNotesSummary {
                    Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button("Update") { updates.checkForUpdates() }
                .controlSize(.small)
                .help("Download and install Dicta \(update.displayVersionString)")
        }
        .padding(10)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var hintRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard").foregroundStyle(.secondary)
            Text("Hold \(Text(preferences.hotkey.title).fontWeight(.semibold).foregroundStyle(.primary)) to dictate, release to insert.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack {
            Button("Settings…", action: showSettings)
                .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .controlSize(.small)
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    private var statusText: String {
        switch controller.state {
        case .idle: return "Ready"
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .error(let message): return message
        }
    }
}

/// "Last transcript" section: clamped to 3 lines with an ellipsis, plus a copy button.
private struct LastTranscriptCard: View {
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Last transcript").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(copied ? .green : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help(copied ? "Copied" : "Copy transcript")
            }
            Text(text)
                .font(.callout)
                .lineLimit(3)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .onChange(of: text) { _, _ in copied = false }
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }
}
