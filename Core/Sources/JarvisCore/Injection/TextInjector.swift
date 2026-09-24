import AppKit
import Foundation
import os

/// Per-app preference for how to insert. Terminals and Chromium/Electron apps answer AX writes
/// with success and do nothing, so they go straight to paste.
public struct InsertionPolicy: Sendable {
    public enum Preference: String, Sendable { case axFirst, pasteFirst, typeOnly, clipboardOnly }

    public var overrides: [String: Preference]

    public static let defaults: [String: Preference] = [
        // Terminals
        "com.apple.Terminal": .pasteFirst,
        "com.googlecode.iterm2": .pasteFirst,
        "com.mitchellh.ghostty": .pasteFirst,
        "dev.warp.Warp-Stable": .pasteFirst,
        "net.kovidgoyal.kitty": .pasteFirst,
        // Chromium / Electron
        "com.google.Chrome": .pasteFirst,
        "com.microsoft.VSCode": .pasteFirst,
        "com.tinyspeck.slackmacgap": .pasteFirst,
        "com.microsoft.teams2": .pasteFirst,
        "com.microsoft.Outlook": .pasteFirst,
        "com.hnc.Discord": .pasteFirst,
        "notion.id": .pasteFirst,
        "com.todesktop.230313mzl4w4u92": .pasteFirst,  // Cursor
    ]

    public init(overrides: [String: Preference] = InsertionPolicy.defaults) {
        self.overrides = overrides
    }

    public func preference(for bundleIdentifier: String?) -> Preference {
        guard let bundleIdentifier else { return .axFirst }
        return overrides[bundleIdentifier] ?? .axFirst
    }
}

/// Outcome of one insertion attempt, for logs and the UI.
public struct InsertionReport: Sendable {
    public var strategy: InsertionStrategy
    public var target: String
    public var attempts: [(InsertionStrategy, String)]
    public var elapsed: Duration
}

/// The insertion ladder: secure-input check -> AX (verified) -> paste -> typing -> clipboard.
@MainActor
public enum TextInjector {
    private static let log = Logger(subsystem: "com.sap.jarvis", category: "inject")

    public static func insert(
        _ text: String,
        policy: InsertionPolicy = InsertionPolicy(),
        forcedStrategy: InsertionStrategy? = nil,
        tap: EventTap = .hid,
        forcePid: Bool = false
    ) async -> InsertionReport {
        let clock = ContinuousClock()
        let start = clock.now
        var attempts: [(InsertionStrategy, String)] = []
        let snapshot = FocusSnapshot.take()
        let target = snapshot.description
        log.info("insert into \(target, privacy: .public)")

        func finish(_ s: InsertionStrategy) -> InsertionReport {
            InsertionReport(strategy: s, target: target, attempts: attempts, elapsed: clock.now - start)
        }

        if SecureInput.isEnabled {
            attempts.append((.clipboard, InsertionError.secureInputActive.description))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return finish(.clipboard)
        }
        // Our own windows (Settings, onboarding) are not a dictation target.
        if let own = Bundle.main.bundleIdentifier, snapshot.bundleIdentifier == own {
            attempts.append((.clipboard, "frontmost app is Jarvis itself"))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return finish(.clipboard)
        }

        let order: [InsertionStrategy]
        if let forcedStrategy {
            order = [forcedStrategy]
        } else {
            // M0 finding (macOS 27): synthetic unmodified keystrokes are dropped, so typing is not
            // part of the default ladder. It stays reachable via `forcedStrategy` / `.typeOnly`.
            switch policy.preference(for: snapshot.bundleIdentifier) {
            case .axFirst: order = [.accessibility, .paste]
            case .pasteFirst: order = [.paste]
            case .typeOnly: order = [.typing]
            case .clipboardOnly: order = []
            }
        }

        for strategy in order {
            do {
                switch strategy {
                case .accessibility:
                    try AXInserter.insert(text, into: snapshot)
                case .paste:
                    let notFrontmost = snapshot.pid != NSWorkspace.shared.frontmostApplication?.processIdentifier
                    let pid = (forcePid || notFrontmost) ? snapshot.pid : nil
                    // Electron/terminal apps can take well over 300 ms to read the pasteboard after
                    // ⌘V; restoring the old clipboard too early makes the paste land the *old* text
                    // or nothing. Give paste-first apps more time.
                    let delay: Duration =
                        policy.preference(for: snapshot.bundleIdentifier) == .pasteFirst
                        ? .milliseconds(900) : .milliseconds(500)
                    try await PasteInserter.insert(text, targetPid: pid, restoreDelay: delay)
                case .typing:
                    try await TypingInserter.insert(text, targetPid: forcePid ? snapshot.pid : nil, tap: tap)
                case .clipboard:
                    continue
                }
                attempts.append((strategy, "ok"))
                log.info("inserted via \(strategy.rawValue, privacy: .public)")
                return finish(strategy)
            } catch {
                attempts.append((strategy, "\(error)"))
                log.notice(
                    "\(strategy.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        attempts.append((.clipboard, "fallback"))
        return finish(.clipboard)
    }
}
