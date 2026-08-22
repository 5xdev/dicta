import AppKit
import ApplicationServices
import AVFoundation

/// Thin wrappers around the three TCC permissions Dicta needs:
///  • Microphone      — AVAudioEngine capture
///  • Accessibility   — CGEventTap for the global hotkey + posting ⌘V to insert text
///  (No speech-recognition permission is needed — transcription happens via Sarvam's API.)
enum Permissions {
    // MARK: Microphone

    static var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    // MARK: Accessibility

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "Dicta would like to control this computer" prompt (once per TCC reset).
    @discardableResult
    static func promptAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: System Settings deep links

    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// Keyboard settings — where the user sets "Press 🌐 key to: Do Nothing" so Fn doesn't open the emoji picker.
    static func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
