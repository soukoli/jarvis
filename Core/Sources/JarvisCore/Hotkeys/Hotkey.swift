import Carbon.HIToolbox
import Foundation

/// A global hotkey: physical key (virtual key code) plus Carbon modifier flags.
/// Stored by key code so it survives keyboard-layout changes (on a Czech layout the physical
/// `;` key prints `ů`, but Cmd+that key still works).
public struct Hotkey: Codable, Sendable, Hashable {
    public var keyCode: UInt32
    public var modifiers: UInt32  // Carbon: cmdKey, shiftKey, optionKey, controlKey

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let cmd = UInt32(cmdKey)
    public static let shift = UInt32(shiftKey)
    public static let option = UInt32(optionKey)
    public static let control = UInt32(controlKey)

    /// Defaults match the Python app: Cmd+; start, Cmd+' stop, Cmd+. cancel (US key positions).
    public static let defaultStart = Hotkey(keyCode: UInt32(kVK_ANSI_Semicolon), modifiers: cmd)
    public static let defaultStop = Hotkey(keyCode: UInt32(kVK_ANSI_Quote), modifiers: cmd)
    public static let defaultCancel = Hotkey(keyCode: UInt32(kVK_ANSI_Period), modifiers: cmd)
    /// Hold to record, release to insert. ⌃⌥Space avoids Spotlight (⌘Space), input switching
    /// (⌃Space) and Raycast/Alfred (⌥Space).
    public static let defaultPushToTalk = Hotkey(keyCode: UInt32(kVK_Space), modifiers: control | option)

    /// Map the Python config's single characters to US key codes.
    public static func fromLegacyCharacter(_ ch: String, modifiers: UInt32 = cmd) -> Hotkey? {
        let map: [String: Int] = [
            ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ".": kVK_ANSI_Period, ",": kVK_ANSI_Comma,
            "/": kVK_ANSI_Slash, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, "\\": kVK_ANSI_Backslash,
            "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "`": kVK_ANSI_Grave,
        ]
        if let code = map[ch] { return Hotkey(keyCode: UInt32(code), modifiers: modifiers) }
        if ch.count == 1, let scalar = ch.lowercased().unicodeScalars.first, scalar.value >= 97, scalar.value <= 122 {
            let letters: [Int] = [
                kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
                kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P,
                kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
                kVK_ANSI_Y, kVK_ANSI_Z,
            ]
            return Hotkey(keyCode: UInt32(letters[Int(scalar.value) - 97]), modifiers: modifiers)
        }
        return nil
    }

    /// Human-readable form using the current keyboard layout, e.g. "⌘;" or "⌘ů".
    public var display: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.cmd != 0 { s += "⌘" }
        return s + (KeyGlyph.glyph(forKeyCode: keyCode) ?? "key \(keyCode)")
    }
}

/// Translate a virtual key code to the character it produces on the current layout.
public enum KeyGlyph {
    public static func glyph(forKeyCode keyCode: UInt32) -> String? {
        let named: [UInt32: String] = [
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Escape): "⎋",
            UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓", UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2",
            UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7",
            UInt32(kVK_F8): "F8",
            UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        ]
        if let n = named[keyCode] { return n }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
