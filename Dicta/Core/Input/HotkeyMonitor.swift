import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Keys that work well for push-to-talk: modifier keys that don't type anything on their own.
enum Hotkey: String, CaseIterable, Identifiable {
    case fn
    case rightOption
    case rightCommand
    case rightControl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fn: return "Fn / 🌐"
        case .rightOption: return "Right ⌥ Option"
        case .rightCommand: return "Right ⌘ Command"
        case .rightControl: return "Right ⌃ Control"
        }
    }

    /// Virtual key code reported in `flagsChanged` events for this modifier.
    var keyCode: Int64 {
        switch self {
        case .fn: return Int64(kVK_Function)
        case .rightOption: return Int64(kVK_RightOption)
        case .rightCommand: return Int64(kVK_RightCommand)
        case .rightControl: return Int64(kVK_RightControl)
        }
    }

    /// Flag that is set while the key is held.
    /// Right-side keys use the *device-specific* bits (NX_DEVICER*KEYMASK from IOKit's IOLLEvent.h) rather than
    /// `.maskAlternate`/`.maskCommand`/`.maskControl`, which are set for either side — otherwise holding the left
    /// twin would mask the right key's release and leave us stuck in "recording".
    var flag: CGEventFlags {
        switch self {
        case .fn: return .maskSecondaryFn
        case .rightOption: return CGEventFlags(rawValue: 0x0000_0040)   // NX_DEVICERALTKEYMASK
        case .rightCommand: return CGEventFlags(rawValue: 0x0000_0010)  // NX_DEVICERCMDKEYMASK
        case .rightControl: return CGEventFlags(rawValue: 0x0000_2000)  // NX_DEVICERCTLKEYMASK
        }
    }
}

enum HotkeyError: LocalizedError {
    case tapCreationFailed
    var errorDescription: String? {
        "Couldn't install the global hotkey listener. Grant Dicta Accessibility access and relaunch."
    }
}

/// Global press/release detection for a modifier key using a listen-only CGEventTap.
/// Requires Accessibility (or Input Monitoring) trust; otherwise `tapCreate` returns nil.
final class HotkeyMonitor {
    var hotkey: Hotkey
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private(set) var isRunning = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    func start() throws {
        guard !isRunning else { return }
        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            throw HotkeyError.tapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        isRunning = true
        Log.hotkey.info("Hotkey monitor started (\(self.hotkey.rawValue, privacy: .public))")
    }

    func stop() {
        guard isRunning else { return }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)      // disabling alone leaves the tap registered with the window server
        }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        isRunning = false
        isDown = false
    }

    // Runs on the main thread (the tap's run loop source is attached to the main run loop).
    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables taps that stall; re-enable immediately. Any release that happened while we were
            // disabled is gone, so drop the held state instead of staying stuck in "recording".
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            setDown(false)
        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keyCode == hotkey.keyCode else { return }
            setDown(event.flags.contains(hotkey.flag))
        default:
            break
        }
    }

    private func setDown(_ down: Bool) {
        guard down != isDown else { return }
        isDown = down
        if down { onPress?() } else { onRelease?() }
    }
}
