import Foundation
import os

/// Unified logging. Transcript text is logged `.private` unless the debug toggle is on, so the
/// user's dictation never lands in system logs by default.
public enum Log {
    public static let subsystem = "com.sap.jarvis"
    public static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    public static let audio = Logger(subsystem: subsystem, category: "audio")
    public static let inject = Logger(subsystem: subsystem, category: "inject")
    public static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    public static let models = Logger(subsystem: subsystem, category: "models")
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let signposter = OSSignposter(subsystem: subsystem, category: "latency")
}
