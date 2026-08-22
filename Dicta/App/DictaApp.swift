import SwiftUI

/// Dicta — push-to-talk dictation for macOS.
/// Menu-bar agent (no Dock icon). Hold the hotkey → speak → release → text is typed into the frontmost app.
@main
struct DictaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().models(from: appDelegate)
        } label: {
            MenuBarLabel().models(from: appDelegate)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().models(from: appDelegate)
        }
    }
}

private extension View {
    /// Every scene sees the same model objects, created once by the AppDelegate.
    func models(from app: AppDelegate) -> some View {
        environmentObject(app.controller)
            .environmentObject(app.preferences)
            .environmentObject(app.preferences.microphone)
            .environmentObject(app.permissions)
            .environmentObject(app.updates)
    }
}
