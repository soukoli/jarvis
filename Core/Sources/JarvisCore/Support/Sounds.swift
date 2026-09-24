import AppKit
import Foundation

/// Audible feedback. Same system sounds as the Python app (Tink on start, Glass on completion).
@MainActor
public enum Sounds {
    public enum Cue: String, Sendable { case start = "Tink", done = "Glass", cancel = "Basso", error = "Sosumi" }

    public static func play(_ cue: Cue) {
        guard let sound = NSSound(named: NSSound.Name(cue.rawValue)) else { return }
        sound.volume = 0.6
        sound.play()
    }
}
