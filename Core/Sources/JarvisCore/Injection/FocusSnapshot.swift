import AppKit
import ApplicationServices
import Foundation

/// What had keyboard focus at a point in time. Taken when recording starts and again right before
/// insertion, so we can insert where the user was looking, not where the mouse wandered.
@MainActor
public struct FocusSnapshot {
    public let takenAt: Date
    public let pid: pid_t?
    public let bundleIdentifier: String?
    public let appName: String?
    /// Focused UI element (system-wide), if Accessibility is granted and the app exposes one.
    public let element: AXUIElement?
    public let role: String?
    public let subrole: String?
    /// True if the element reports `AXSelectedText` as settable, the precondition for the AX path.
    public let selectedTextSettable: Bool
    /// True if the element reports `AXValue` as settable (fallback AX path, e.g. some text areas).
    public let valueSettable: Bool
    /// How the element was found, or why it was not, for diagnostics.
    public let lookup: String

    public static func take() -> FocusSnapshot {
        let app = NSWorkspace.shared.frontmostApplication
        var element: AXUIElement?
        var role: String?
        var subrole: String?
        var selSettable = false
        var valSettable = false
        var lookup = "ax-not-trusted"

        if AXIsProcessTrusted() {
            // 1. System-wide focused element.
            let systemWide = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(systemWide, 0.5)
            var focused: CFTypeRef?
            let sysErr = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
            if sysErr == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                element = (focused as! AXUIElement)
                lookup = "system-wide"
            } else if let pid = app?.processIdentifier {
                // 2. Ask the frontmost application directly; some apps only answer this way.
                let appEl = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(appEl, 0.5)
                var appFocused: CFTypeRef?
                let appErr = AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &appFocused)
                if appErr == .success, let appFocused, CFGetTypeID(appFocused) == AXUIElementGetTypeID() {
                    element = (appFocused as! AXUIElement)
                    lookup = "app-element (system-wide err \(sysErr.rawValue))"
                } else {
                    lookup = "none (system-wide err \(sysErr.rawValue), app err \(appErr.rawValue))"
                }
            } else {
                lookup = "none (system-wide err \(sysErr.rawValue), no frontmost app)"
            }
            if let el = element {
                AXUIElementSetMessagingTimeout(el, 0.5)
                role = el.stringAttribute(kAXRoleAttribute)
                subrole = el.stringAttribute(kAXSubroleAttribute)
                selSettable = el.isSettable(kAXSelectedTextAttribute)
                valSettable = el.isSettable(kAXValueAttribute)
            }
        }

        return FocusSnapshot(
            takenAt: Date(),
            pid: app?.processIdentifier,
            bundleIdentifier: app?.bundleIdentifier,
            appName: app?.localizedName,
            element: element,
            role: role,
            subrole: subrole,
            selectedTextSettable: selSettable,
            valueSettable: valSettable,
            lookup: lookup
        )
    }

    /// The focused element's `AXValue` (text content) trimmed for logs, or nil if unavailable.
    public func valueExcerpt(maxLength: Int = 120) -> String? {
        guard let element, let value = element.stringAttribute(kAXValueAttribute) else { return nil }
        let flat = value.replacingOccurrences(of: "\n", with: "⏎")
        return flat.count > maxLength ? "…" + flat.suffix(maxLength) : flat
    }

    public var description: String {
        "\(appName ?? "?") (\(bundleIdentifier ?? "?")) role=\(role ?? "-")\(subrole.map { "/\($0)" } ?? "") selectedTextSettable=\(selectedTextSettable) valueSettable=\(valueSettable) via=\(lookup)"
    }
}

extension AXUIElement {
    func stringAttribute(_ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    func isSettable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(self, name as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

    /// Current selected text range (location/length in UTF-16 units) if the element exposes one.
    func selectedRange() -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
}
