import AVFoundation
import AppKit
import ApplicationServices
import Foundation

/// The TCC permissions Jarvis needs. Input Monitoring is intentionally absent: Carbon hotkeys and
/// CGEvent posting only need Accessibility.
public enum Permission: String, CaseIterable, Sendable {
    case microphone
    case accessibility

    public var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        }
    }

    /// Deep link into System Settings > Privacy & Security.
    public var settingsURL: URL {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        }
    }
}

public enum PermissionState: String, Sendable {
    case granted, denied, notDetermined
}

@MainActor
public enum Permissions {
    public static func state(of permission: Permission) -> PermissionState {
        switch permission {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        }
    }

    /// Whether this process may post synthetic keyboard events (needed for Cmd+V and typing).
    public static var canPostEvents: Bool { CGPreflightPostEventAccess() }

    /// Ask the system for a permission. Microphone shows the native sheet; Accessibility opens the
    /// system prompt that points at System Settings.
    public static func request(_ permission: Permission) async -> PermissionState {
        switch permission {
        case .microphone:
            let ok = await AVCaptureDevice.requestAccess(for: .audio)
            return ok ? .granted : .denied
        case .accessibility:
            // Literal key instead of the `kAXTrustedCheckOptionPrompt` global (not Sendable in Swift 6).
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            if !trusted { _ = CGRequestPostEventAccess() }
            return trusted ? .granted : .denied
        }
    }

    public static func openSettings(for permission: Permission) {
        NSWorkspace.shared.open(permission.settingsURL)
    }

    public static func summary() -> [(Permission, PermissionState)] {
        Permission.allCases.map { ($0, state(of: $0)) }
    }
}
