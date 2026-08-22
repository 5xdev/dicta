import CoreAudio
import Foundation

/// A microphone (or any device with input channels) as seen by CoreAudio.
/// Identified by `uid`, which is stable across reboots and re-plugs — so it is both what we persist and what
/// equality means here. (CoreAudio's `AudioDeviceID` is only valid for the current session, so it is not kept.)
struct AudioInputDevice: Identifiable, Equatable {
    let uid: String
    let name: String

    var id: String { uid }
}

/// CoreAudio queries for input devices. All calls are cheap and synchronous.
enum AudioInputDevices {
    /// Every device that currently exposes at least one input channel, in CoreAudio's order.
    static func all() -> [AudioInputDevice] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard inputChannelCount(of: id) > 0,
                  !isPrivateAggregate(id),
                  let uid = string(kAudioDevicePropertyDeviceUID, of: id),
                  let name = string(kAudioObjectPropertyName, of: id) else { return nil }
            return AudioInputDevice(uid: uid, name: name)
        }
    }

    /// The system-wide default input device, if any.
    static func systemDefault() -> AudioInputDevice? {
        var address = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown,
              let uid = string(kAudioDevicePropertyDeviceUID, of: id),
              let name = string(kAudioObjectPropertyName, of: id) else { return nil }
        return AudioInputDevice(uid: uid, name: name)
    }

    /// Calls `handler` on the main queue whenever a device is added/removed or the default input changes.
    /// Keep the returned token alive for as long as you want notifications; it deregisters on deinit.
    static func observeChanges(_ handler: @escaping () -> Void) -> AnyObject {
        ChangeObserver(handler)
    }

    // MARK: - Internals

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private final class ChangeObserver {
        private let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
        ]
        private let block: AudioObjectPropertyListenerBlock

        init(_ handler: @escaping () -> Void) {
            block = { _, _ in handler() }
            for selector in selectors {
                var address = AudioInputDevices.address(selector)
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            }
        }

        deinit {
            for selector in selectors {
                var address = AudioInputDevices.address(selector)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            }
        }
    }

    /// AVAudioEngine wraps the default input in a process-private aggregate device ("CADefaultDeviceAggregate-…")
    /// which CoreAudio still lists to us. It isn't a microphone the user can choose, so hide it.
    private static func isPrivateAggregate(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr,
              transport == kAudioDeviceTransportTypeAggregate else { return false }

        address.mSelector = kAudioAggregateDevicePropertyComposition
        var composition: Unmanaged<CFDictionary>?
        size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        let status = withUnsafeMutablePointer(to: &composition) { ptr in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let composition else {
            // Can't read the composition — fall back to the name CoreAudio gives these wrappers.
            return string(kAudioDevicePropertyDeviceUID, of: id)?.hasPrefix("CADefaultDeviceAggregate") == true
        }
        let dict = composition.takeRetainedValue() as NSDictionary
        let isPrivate = (dict[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue ?? false
        return isPrivate || (dict[kAudioAggregateDeviceUIDKey] as? String)?.hasPrefix("CADefaultDeviceAggregate") == true
    }

    private static func inputChannelCount(of id: AudioDeviceID) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
