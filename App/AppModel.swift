import AppKit
import JarvisCore
import Observation
import ServiceManagement
import SwiftUI
import UserNotifications

/// Application state machine and glue between hotkeys, the dictation pipeline, injection and UI.
/// Everything here is MainActor; the heavy work lives in `JarvisCore` actors.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum State: Equatable { case idle, recording, processing }

    let settings = SettingsStore.shared
    let models: ModelManager
    let hotkeys = HotkeyManager()

    private(set) var state: State = .idle
    private(set) var partialText = ""
    private(set) var lastText = ""
    private(set) var lastInsertion: InsertionStrategy?
    private(set) var lastError: String?
    private(set) var lastLatencySeconds: Double?
    private(set) var permissions: [(Permission, PermissionState)] = []
    private(set) var silentInputDetected = false
    private(set) var inputDevices: [AudioInputDevice] = []
    var hotkeyError: String?

    /// Bumped on every start and cancel. A finished session only acts if its generation matches.
    private var generation: UInt64 = 0
    private var session: DictationSession?
    private var permissionTimer: Timer?
    private var onboarding: OnboardingWindowController?

    private init() {
        models = ModelManager(vadConfig: SettingsStore.shared.vadConfig)
    }

    // MARK: - Lifecycle

    func launch() {
        Log.app.info(
            "Jarvis \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?", privacy: .public) launching"
        )
        refreshPermissions()
        refreshDevices()
        registerHotkeys()
        models.load(settings.model)
        requestNotificationAuthorization()

        let missing = permissions.contains { $0.1 != .granted }
        if !settings.onboardingDone || missing {
            showOnboarding()
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    func shutdown() {
        hotkeys.unregisterAll()
        Task { await session?.cancel() }
    }

    // MARK: - Status for the menu bar

    /// Status-item image. Template (system-tinted) when idle, red microphone while recording,
    /// orange waveform while the last chunk is being transcribed and inserted.
    var menuBarImage: NSImage {
        let config = NSImage.SymbolConfiguration(textStyle: .body, scale: .large)
        switch state {
        case .idle:
            let name = permissionsMissing ? "exclamationmark.triangle" : (models.status.isReady ? "mic" : "mic.slash")
            let image = NSImage(systemSymbolName: name, accessibilityDescription: statusText)!
                .withSymbolConfiguration(config)!
            image.isTemplate = true
            return image
        case .recording:
            return Self.tintedSymbol("mic.fill", color: .systemRed, config: config, description: statusText)
        case .processing:
            return Self.tintedSymbol("waveform", color: .systemOrange, config: config, description: statusText)
        }
    }

    private static func tintedSymbol(
        _ name: String, color: NSColor, config: NSImage.SymbolConfiguration, description: String
    ) -> NSImage {
        let palette = config.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)!
            .withSymbolConfiguration(palette)!
        image.isTemplate = false
        return image
    }

    var statusSymbol: String {
        switch state {
        case .idle: return permissionsMissing ? "mic.badge.xmark" : (models.status.isReady ? "mic" : "mic.slash")
        case .recording: return "mic.fill"
        case .processing: return "waveform"
        }
    }

    var statusText: String {
        switch state {
        case .idle:
            if permissionsMissing { return "Permissions needed" }
            if needsRelaunchForPermissions { return "Restart needed to apply permissions" }
            return models.status.isReady ? "Ready" : models.status.label
        case .recording: return "Recording…"
        case .processing: return "Transcribing…"
        }
    }

    var permissionsMissing: Bool { permissions.contains { $0.1 != .granted } }

    // MARK: - Recording control

    func start() {
        guard state == .idle else { return }
        guard let transcriber = models.transcriber, let chunker = models.chunker else {
            notify(title: "Model not ready", body: models.status.label)
            Sounds.play(.error)
            return
        }
        guard Permissions.state(of: .microphone) != .denied else {
            notify(
                title: "Microphone access denied",
                body: "Enable Jarvis in System Settings → Privacy & Security → Microphone.")
            showOnboarding()
            return
        }

        generation += 1
        let gen = generation
        let device = AudioDevices.recordingDevice(
            uid: settings.deviceUID, name: settings.deviceName, preferBuiltIn: settings.preferBuiltInMic)
        let session = DictationSession(
            transcriber: transcriber,
            chunker: chunker,
            hint: settings.languageHint,
            prompt: settings.glossary.isEmpty ? nil : settings.glossary,
            device: device
        )
        self.session = session
        partialText = ""
        lastError = nil
        silentInputDetected = false
        state = .recording
        if settings.startSound { Sounds.play(.start) }

        Task {
            do {
                try await session.start()
            } catch {
                guard gen == self.generation else { return }
                self.state = .idle
                self.session = nil
                self.lastError = String(describing: error)
                Sounds.play(.error)
                self.notify(title: "Could not start recording", body: String(describing: error))
                return
            }
            for await event in session.events {
                guard gen == self.generation else { break }
                switch event {
                case .partial(let text): self.partialText = text
                case .chunk(let index, _, let audio, let decode):
                    Log.pipeline.debug(
                        "chunk \(index) \(audio, format: .fixed(precision: 1)) s audio in \(decode, format: .fixed(precision: 2)) s"
                    )
                case .silentInput:
                    self.silentInputDetected = true
                    self.notify(
                        title: "Microphone is silent",
                        body: "All-zero audio for 2 s. Check the input device and Microphone permission.")
                case .captureFailed(let message):
                    self.lastError = message
                    self.notify(title: "No audio from the microphone", body: message)
                    Sounds.play(.error)
                    self.cancel()
                }
            }
        }
    }

    func stop() {
        guard state == .recording, let session else { return }
        let gen = generation
        state = .processing
        let clock = ContinuousClock()
        let started = clock.now
        Task {
            let text = await session.stop()
            guard gen == self.generation else { return }
            self.session = nil
            await self.deliver(text)
            self.lastLatencySeconds =
                Double((clock.now - started).components.seconds) + Double((clock.now - started).components.attoseconds)
                / 1e18
            self.state = .idle
        }
    }

    func cancel() {
        guard state != .idle, let session else { return }
        generation += 1
        self.session = nil
        state = .idle
        partialText = ""
        Sounds.play(.cancel)
        Task { await session.cancel() }
    }

    func toggle() {
        switch state {
        case .idle: start()
        case .recording: stop()
        case .processing: break
        }
    }

    // MARK: - Delivery

    private func deliver(_ text: String) async {
        lastText = text
        guard !text.isEmpty else {
            lastInsertion = nil
            notify(title: "Nothing recognized", body: "No speech was detected.")
            return
        }
        switch settings.insertionMode {
        case .copyOnly:
            copyToClipboard(text)
            lastInsertion = .clipboard
        case .insert, .insertAndCopy:
            let report = await TextInjector.insert(text)
            lastInsertion = report.strategy
            if report.strategy == .clipboard {
                let blockedByPermission = report.attempts.contains { $0.1.contains("Accessibility not granted") }
                if blockedByPermission {
                    refreshPermissions()
                    if needsRelaunchForPermissions {
                        notify(
                            title: "Copied to clipboard. Restart Jarvis to insert at the cursor",
                            body:
                                "Accessibility was granted after Jarvis started; macOS applies it on the next launch. Use “Restart Jarvis” in the menu."
                        )
                    } else {
                        notify(
                            title: "Copied to clipboard. Accessibility needed",
                            body:
                                "Allow Jarvis under System Settings → Privacy & Security → Accessibility to insert at the cursor."
                        )
                        showOnboarding()
                    }
                } else {
                    notify(
                        title: "Copied to clipboard",
                        body:
                            "Could not insert into \(report.target.split(separator: " (").first ?? "the app"). Press ⌘V to paste."
                    )
                }
            } else if settings.insertionMode == .insertAndCopy {
                copyToClipboard(text)
            }
            Log.inject.info(
                "delivered via \(report.strategy.rawValue, privacy: .public) in \(String(describing: report.elapsed), privacy: .public)"
            )
        }
        if settings.completionSound { Sounds.play(.done) }
    }

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: - Settings actions

    func selectLanguage(_ id: String) { settings.language = id }

    func selectModel(_ model: WhisperModel) {
        settings.modelKey = model.id
        models.load(model)
    }

    func selectDevice(_ device: AudioInputDevice?) {
        settings.deviceUID = device?.uid
        settings.deviceName = device?.name
    }

    func applyVADSettings() { models.updateVAD(settings.vadConfig) }

    func refreshDevices() { inputDevices = AudioDevices.inputDevices() }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Launch at login: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Hotkeys

    func registerHotkeys() {
        hotkeys.unregisterAll()
        hotkeyError = nil
        do {
            try hotkeys.register(settings.hotkeyStart) { [weak self] phase in if phase == .pressed { self?.start() } }
            try hotkeys.register(settings.hotkeyStop) { [weak self] phase in if phase == .pressed { self?.stop() } }
            try hotkeys.register(settings.hotkeyCancel) { [weak self] phase in if phase == .pressed { self?.cancel() } }
            if settings.pushToTalkEnabled {
                try hotkeys.register(settings.hotkeyPushToTalk) { [weak self] phase in self?.pushToTalk(phase) }
            }
        } catch {
            hotkeyError = String(describing: error)
            Log.hotkey.error("\(String(describing: error), privacy: .public)")
        }
    }

    /// Hold to record, release to insert. A tap shorter than 300 ms is treated as accidental.
    private var pushToTalkPressedAt: ContinuousClock.Instant?
    private var pushToTalkActive = false

    private func pushToTalk(_ phase: HotkeyManager.Phase) {
        switch phase {
        case .pressed:
            guard state == .idle, !pushToTalkActive else { return }
            pushToTalkActive = true
            pushToTalkPressedAt = ContinuousClock.now
            start()
        case .released:
            guard pushToTalkActive else { return }
            pushToTalkActive = false
            let held = pushToTalkPressedAt.map { ContinuousClock.now - $0 } ?? .zero
            pushToTalkPressedAt = nil
            if state == .recording {
                if held < .milliseconds(300) { cancel() } else { stop() }
            }
        }
    }

    // MARK: - Permissions & onboarding

    /// True when Accessibility is granted but this process still cannot post keyboard events:
    /// macOS caches that decision at launch, so a grant made while Jarvis runs needs a relaunch.
    private(set) var needsRelaunchForPermissions = false

    func refreshPermissions() {
        permissions = Permissions.summary()
        let axGranted = permissions.first { $0.0 == .accessibility }?.1 == .granted
        if axGranted, !Permissions.canPostEvents {
            _ = CGRequestPostEventAccess()
            needsRelaunchForPermissions = !Permissions.canPostEvents
        } else {
            needsRelaunchForPermissions = false
        }
    }

    /// Start a fresh instance and quit this one (used after permissions change).
    func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func requestPermission(_ p: Permission) {
        Task {
            _ = await Permissions.request(p)
            refreshPermissions()
        }
    }

    func showOnboarding() {
        if onboarding == nil { onboarding = OnboardingWindowController(model: self) }
        onboarding?.show()
    }

    func finishOnboarding() {
        settings.onboardingDone = true
        onboarding?.close()
    }

    /// Issue tracker on SAP GitHub. Pre-fills the environment so colleagues do not have to.
    static let issuesURL = URL(string: "https://github.tools.sap/I314819/sap-jarvis/issues")!

    func reportIssue() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let body = """
            **What happened**


            **Expected**


            ---
            SAP Jarvis \(version) · \(os) · model \(settings.model.variant) · engine \(models.status.label)
            """
        var components = URLComponents(
            url: Self.issuesURL.appendingPathComponent("new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        NSWorkspace.shared.open(components.url ?? Self.issuesURL)
    }

    // MARK: - Notifications

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.app.notice("notification failed: \(error.localizedDescription, privacy: .public)") }
        }
    }
}
