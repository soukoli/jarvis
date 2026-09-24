import Carbon.HIToolbox
import Foundation

/// Global hotkeys via Carbon `RegisterEventHotKey`. No TCC permission required, delivers both
/// press and release (so hold-to-talk is possible later), and wins over app shortcuts.
@MainActor
public final class HotkeyManager {
    public enum Phase: Sendable { case pressed, released }
    public typealias Handler = @MainActor (Phase) -> Void

    private struct Registration {
        var ref: EventHotKeyRef
        var handler: Handler
    }

    private var registrations: [UInt32: Registration] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1
    private static let signature: OSType = 0x4A525653  // 'JRVS'

    public init() {}

    /// Register `hotkey`; returns an id for `unregister`. Throws if the combination is taken.
    @discardableResult
    public func register(_ hotkey: Hotkey, handler: @escaping Handler) throws -> UInt32 {
        try installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            throw HotkeyError.registrationFailed(status)
        }
        registrations[id] = Registration(ref: ref, handler: handler)
        Log.hotkey.info("registered \(hotkey.display, privacy: .public) as #\(id)")
        return id
    }

    public func unregister(_ id: UInt32) {
        guard let reg = registrations.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(reg.ref)
    }

    public func unregisterAll() {
        for id in Array(registrations.keys) { unregister(id) }
    }

    // MARK: - Carbon plumbing

    private func installHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetEventDispatcherTarget(), hotkeyEventHandler, types.count, &types, userData, &eventHandlerRef)
        guard status == noErr else { throw HotkeyError.handlerInstallFailed(status) }
    }

    fileprivate func dispatch(id: UInt32, kind: UInt32) {
        guard let reg = registrations[id] else { return }
        reg.handler(kind == UInt32(kEventHotKeyReleased) ? .released : .pressed)
    }

    isolated deinit {
        // Runs on the MainActor (SE-0371), so Carbon refs can be released safely.
        for reg in registrations.values { UnregisterEventHotKey(reg.ref) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}

/// C callback. Carbon calls it on the main thread (the event dispatcher target), so hopping to
/// the MainActor is an assertion, not a dispatch.
private let hotkeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr else { return status }
    let kind = GetEventKind(event)
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.dispatch(id: hotKeyID.id, kind: kind)
    }
    return noErr
}

public enum HotkeyError: Error, CustomStringConvertible {
    case registrationFailed(OSStatus)
    case handlerInstallFailed(OSStatus)

    public var description: String {
        switch self {
        case .registrationFailed(let s): return "Could not register hotkey (OSStatus \(s)); is it taken by another app?"
        case .handlerInstallFailed(let s): return "Could not install hotkey handler (OSStatus \(s))"
        }
    }
}
