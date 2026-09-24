import Carbon.HIToolbox
import Foundation

/// Secure event input is on while a password field (or Terminal with "Secure Keyboard Entry") has
/// focus. Synthetic keystrokes are dropped and AX writes are refused, so Jarvis must not try.
public enum SecureInput {
    public static var isEnabled: Bool { IsSecureEventInputEnabled() }
}
