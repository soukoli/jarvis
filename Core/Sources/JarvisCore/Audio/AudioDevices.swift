import CoreAudio
import Foundation

/// One audio input device as CoreAudio sees it.
public struct AudioInputDevice: Sendable, Identifiable, Hashable {
    public enum Transport: String, Sendable { case builtIn, bluetooth, usb, displayPort, virtual, other }

    public var id: AudioDeviceID
    public var uid: String
    public var name: String
    public var isDefault: Bool
    public var transport: Transport

    /// Bluetooth microphones use the HFP profile: 8 to 24 kHz, a wake-up delay after the stream
    /// starts, and sometimes no audio at all. Dictation is better off on the built-in mic.
    public var isBluetooth: Bool { transport == .bluetooth }
}

/// CoreAudio device enumeration and the name-based fallback the Python app used
/// (exact name, then substring, then system default).
public enum AudioDevices {
    public static func inputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }

        let defaultID = defaultInputDeviceID()
        return ids.compactMap { id in
            guard inputChannelCount(id) > 0 else { return nil }
            guard let name = stringProperty(id, kAudioObjectPropertyName),
                let uid = stringProperty(id, kAudioDevicePropertyDeviceUID)
            else { return nil }
            return AudioInputDevice(
                id: id, uid: uid, name: name, isDefault: id == defaultID, transport: transport(of: id))
        }
    }

    public static func defaultInputDevice() -> AudioInputDevice? {
        inputDevices().first { $0.isDefault }
    }

    public static func builtInMicrophone() -> AudioInputDevice? {
        inputDevices().first { $0.transport == .builtIn }
    }

    /// The device Jarvis should record from: the user's explicit choice, else the system default,
    /// except that a Bluetooth default is swapped for the built-in mic when `preferBuiltIn` is on.
    public static func recordingDevice(uid: String?, name: String?, preferBuiltIn: Bool) -> AudioInputDevice? {
        if let chosen = resolve(uid: uid, name: name) { return chosen }
        guard preferBuiltIn, let def = defaultInputDevice(), def.isBluetooth else { return nil }
        return builtInMicrophone()
    }

    private static func transport(of id: AudioDeviceID) -> AudioInputDevice.Transport {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return .other }
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeThunderbolt, kAudioDeviceTransportTypeHDMI:
            return .displayPort
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return .virtual
        default: return .other
        }
    }

    public static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
            id != 0
        else { return nil }
        return id
    }

    /// Resolve the user's saved device: by UID, then exact name, then substring, else nil (= default).
    public static func resolve(uid: String?, name: String?) -> AudioInputDevice? {
        let devices = inputDevices()
        if let uid, let d = devices.first(where: { $0.uid == uid }) { return d }
        guard let name, !name.isEmpty else { return nil }
        if let d = devices.first(where: { $0.name == name }) { return d }
        let lower = name.lowercased()
        return devices.first { $0.name.lowercased().contains(lower) || lower.contains($0.name.lowercased()) }
    }

    // MARK: - Helpers

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
