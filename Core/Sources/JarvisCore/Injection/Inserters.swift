import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Which mechanism put the text into the target app.
public enum InsertionStrategy: String, Sendable, CaseIterable {
    case accessibility  // AXSelectedText write, verified
    case paste  // Cmd+V with transient pasteboard, restored afterwards
    case typing  // CGEventKeyboardSetUnicodeString
    case clipboard  // Left on the clipboard only
}

public enum InsertionError: Error, CustomStringConvertible {
    case secureInputActive
    case noFocusedElement
    case notSettable
    case axWriteFailed(AXError)
    case verificationFailed
    case cannotPostEvents
    case eventCreationFailed

    public var description: String {
        switch self {
        case .secureInputActive: return "Secure input is active (password field?)"
        case .noFocusedElement: return "No focused UI element"
        case .notSettable: return "Focused element does not accept AXSelectedText"
        case .axWriteFailed(let e): return "AX write failed (\(e.rawValue))"
        case .verificationFailed: return "AX write reported success but the text did not appear"
        case .cannotPostEvents: return "Process may not post keyboard events (Accessibility not granted)"
        case .eventCreationFailed: return "Could not create CGEvent"
        }
    }
}

// MARK: - Accessibility path

@MainActor
public enum AXInserter {
    /// Replace the current selection (or insert at the caret) with `text` and verify it landed.
    public static func insert(_ text: String, into snapshot: FocusSnapshot) throws {
        guard let element = snapshot.element else { throw InsertionError.noFocusedElement }
        guard snapshot.selectedTextSettable else { throw InsertionError.notSettable }

        let before = element.selectedRange()
        let err = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        guard err == .success else { throw InsertionError.axWriteFailed(err) }

        // Verification: caret should have advanced by the inserted length, or the value should
        // now contain the text. Some apps (Electron, Java) answer .success and do nothing.
        if let before, let after = element.selectedRange() {
            let expected = before.location + text.utf16.count
            if after.location == expected, after.length == 0 { return }
        }
        if let value = element.stringAttribute(kAXValueAttribute), value.contains(text) { return }
        throw InsertionError.verificationFailed
    }
}

// MARK: - Paste path

@MainActor
public enum PasteInserter {
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// Put `text` on the pasteboard, send Cmd+V, then restore the previous pasteboard contents.
    /// - Parameter targetPid: post directly to this process when it is not frontmost (launcher panels).
    /// - Parameter restoreDelay: how long to wait before restoring; the target must have read the
    ///   pasteboard by then. VoiceInk uses 250 ms; Electron apps can be slower.
    public static func insert(
        _ text: String, targetPid: pid_t? = nil, restoreDelay: Duration = .milliseconds(300)
    ) async throws {
        guard CGPreflightPostEventAccess() else { throw InsertionError.cannotPostEvents }

        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Tell clipboard managers not to record this entry.
        pasteboard.setData(Data(), forType: transientType)
        pasteboard.setData(Data(), forType: concealedType)
        let ourChangeCount = pasteboard.changeCount

        try postCommandV(targetPid: targetPid)

        try await Task.sleep(for: restoreDelay)
        // Only restore if nobody else has written to the pasteboard in the meantime.
        if pasteboard.changeCount == ourChangeCount {
            restore(saved, to: pasteboard)
        }
    }

    private static func postCommandV(targetPid: pid_t?) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw InsertionError.eventCreationFailed
        }
        // Make sure our synthetic events are not merged with physical key state.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)

        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else {
            throw InsertionError.eventCreationFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        if let targetPid {
            down.postToPid(targetPid)
            usleep(10_000)
            up.postToPid(targetPid)
        } else {
            down.post(tap: .cghidEventTap)
            usleep(10_000)
            up.post(tap: .cghidEventTap)
        }
    }

    private struct SavedItem { var data: [NSPasteboard.PasteboardType: Data] }

    private static func snapshot(_ pb: NSPasteboard) -> [SavedItem] {
        (pb.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let d = item.data(forType: type) { data[type] = d }
            }
            return SavedItem(data: data)
        }
    }

    private static func restore(_ items: [SavedItem], to pb: NSPasteboard) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        let newItems: [NSPasteboardItem] = items.map { saved in
            let item = NSPasteboardItem()
            for (type, data) in saved.data { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(newItems)
    }
}

// MARK: - Typing path

/// Where synthetic events are posted. Spike option; the default is decided in M0.
public enum EventTap: String, Sendable, CaseIterable {
    case hid, session, annotated

    var location: CGEventTapLocation {
        switch self {
        case .hid: return .cghidEventTap
        case .session: return .cgSessionEventTap
        case .annotated: return .cgAnnotatedSessionEventTap
        }
    }
}

@MainActor
public enum TypingInserter {
    /// Type `text` as Unicode key events. Slow but works where paste is intercepted.
    public static func insert(
        _ text: String, targetPid: pid_t? = nil, tap: EventTap = .hid, batchSize: Int = 20,
        gap: Duration = .milliseconds(5)
    ) async throws {
        guard CGPreflightPostEventAccess() else { throw InsertionError.cannotPostEvents }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw InsertionError.eventCreationFailed
        }

        var units = Array(text.utf16)
        while !units.isEmpty {
            // Do not split a surrogate pair across batches.
            var take = min(batchSize, units.count)
            if take < units.count, UTF16.isLeadSurrogate(units[take - 1]) { take -= 1 }
            let chunk = Array(units.prefix(take))
            units.removeFirst(take)

            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw InsertionError.eventCreationFailed
            }
            chunk.withUnsafeBufferPointer { buf in
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
            if let targetPid {
                down.postToPid(targetPid)
                up.postToPid(targetPid)
            } else {
                down.post(tap: tap.location)
                up.post(tap: tap.location)
            }
            try await Task.sleep(for: gap)
        }
    }
}
