import AppKit
import Carbon.HIToolbox

/// Puts transcribed text into whatever app has focus.
/// Strategy: stash the pasteboard, write our text, synthesize ⌘V, then restore the pasteboard.
/// This is the most universally compatible approach (works in Electron, terminals, browsers, remote desktops).
/// There is no way to observe the target app consuming the paste, so the restore is a grace period: long enough
/// for slow apps (Electron, remote desktops) to read the pasteboard, and skipped entirely if anything else wrote
/// to the pasteboard in the meantime (the user copied something, or a second transcript was inserted).
/// TODO: add an Accessibility-API path (kAXSelectedTextAttribute) for apps that support it, to avoid touching the clipboard.
enum TextInserter {
    /// Grace period before the previous pasteboard contents are put back — see above.
    private static let restoreDelay: TimeInterval = 1.0

    @MainActor
    static func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount
        postCommandV()
        Log.insert.info("Inserted \(text.count, privacy: .public) characters via ⌘V")

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            guard pasteboard.changeCount == ourChangeCount else {
                Log.insert.info("Pasteboard changed since insert — leaving it alone")
                return
            }
            restore(saved, to: pasteboard)
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
