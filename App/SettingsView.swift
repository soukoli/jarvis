import JarvisCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gear") }
            HotkeySettings().tabItem { Label("Hotkeys", systemImage: "keyboard") }
            AudioSettings().tabItem { Label("Audio", systemImage: "mic") }
            ModelSettings().tabItem { Label("Models", systemImage: "cpu") }
            PermissionSettings().tabItem { Label("Permissions", systemImage: "lock.shield") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520)
        .environment(model)
    }
}

// MARK: - Privacy

/// Plain statement of what the app does with data, plus the two controls a user needs: see the
/// files it keeps and wipe its settings. Keep this in sync with README "Privacy".
struct PrivacySettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false
    @State private var confirmDeleteModels = false

    var body: some View {
        Form {
            Section("Your voice and text") {
                PrivacyRow(
                    symbol: "waveform", title: "Speech is recognized on this Mac",
                    detail:
                        "Audio stays in memory and is discarded after each recording. Nothing is written to disk and nothing is sent anywhere."
                )
                PrivacyRow(
                    symbol: "text.cursor", title: "Text goes only where you dictate it",
                    detail:
                        "Into the focused app, or to the clipboard when you choose so. The clipboard copy is marked transient so clipboard managers skip it, and your previous clipboard is restored."
                )
                PrivacyRow(
                    symbol: "doc.text.magnifyingglass", title: "Transcripts are never logged",
                    detail: "Diagnostics record timings, sizes and device names only.")
            }
            Section("Network") {
                PrivacyRow(
                    symbol: "arrow.down.circle", title: "One download, no telemetry",
                    detail:
                        "The speech and voice-detection models are fetched once from huggingface.co. There is no analytics, crash reporting or update check. “Report an Issue” opens SAP GitHub in your browser on request."
                )
            }
            Section("Stored on this Mac") {
                PrivacyRow(
                    symbol: "internaldrive", title: "Settings",
                    detail:
                        "Language, shortcuts, microphone, vocabulary and toggles in the app's preferences (com.sap.jarvis)."
                )
                PrivacyRow(
                    symbol: "cpu", title: "Models",
                    detail: "~/Library/Application Support/Jarvis/Models (about 1.6 GB).")
                HStack {
                    Button("Show Models Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([WhisperModel.defaultDownloadBase])
                    }
                    Button("Reset Settings…", role: .destructive) { confirmReset = true }
                    Button("Delete Models…", role: .destructive) { confirmDeleteModels = true }
                }
                .controlSize(.small)
            }
            Section("Permissions") {
                PrivacyRow(symbol: "mic", title: "Microphone", detail: "Only while you record.")
                PrivacyRow(
                    symbol: "accessibility", title: "Accessibility",
                    detail:
                        "Used solely to place text at the cursor and to send ⌘V. Jarvis does not read screen content or keystrokes."
                )
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings to defaults?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                model.settings.resetToDefaults()
                model.registerHotkeys()
            }
        } message: {
            Text("Shortcuts, language, microphone and vocabulary return to defaults. Downloaded models are kept.")
        }
        .confirmationDialog("Delete downloaded models and quit Jarvis?", isPresented: $confirmDeleteModels) {
            Button("Delete and Quit", role: .destructive) { model.deleteModelsAndQuit() }
        } message: {
            Text("Frees about 1.6 GB. The next launch downloads the model again. Use this before uninstalling.")
        }
    }
}

struct PrivacyRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Language") {
                Picker("Spoken language", selection: $settings.language) {
                    ForEach(Language.all) { Text("\($0.flag) \($0.name)").tag($0.id) }
                }
                if settings.language == "auto" {
                    PreferredLanguagesPicker(selection: $settings.preferredLanguages)
                    Text(
                        "With a preference list, auto-detect only chooses among those languages. Leave empty to allow any."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Output") {
                Picker("After transcription", selection: $settings.insertionMode) {
                    ForEach(InsertionMode.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Vocabulary") {
                TextField("Words the model should spell correctly", text: $settings.glossary, axis: .vertical)
                    .lineLimit(2...4)
                Text(
                    "Comma-separated names and terms, e.g. “SAP, BTP, Jira, pull request”. Used as the model's initial prompt."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Feedback") {
                Toggle("Sound when recording starts", isOn: $settings.startSound)
                Toggle("Sound when text is inserted", isOn: $settings.completionSound)
            }
            Section("Startup") {
                Toggle(
                    "Launch Jarvis at login",
                    isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            }
        }
        .formStyle(.grouped)
    }
}

struct PreferredLanguagesPicker: View {
    @Binding var selection: [String]

    var body: some View {
        LabeledContent("Prefer") {
            FlowLayout(spacing: 6) {
                ForEach(Language.all.filter { $0.id != "auto" }) { lang in
                    let on = selection.contains(lang.id)
                    Button {
                        if on { selection.removeAll { $0 == lang.id } } else { selection.append(lang.id) }
                    } label: {
                        Text("\(lang.flag) \(lang.id.uppercased())")
                            .font(.callout)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(
                                on ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Minimal wrapping layout for the language chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Hotkeys

struct HotkeySettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                HotkeyRecorder(title: "Start recording", hotkey: $settings.hotkeyStart)
                HotkeyRecorder(title: "Stop and insert", hotkey: $settings.hotkeyStop)
                HotkeyRecorder(title: "Cancel", hotkey: $settings.hotkeyCancel)
            } header: {
                Text("Toggle mode")
            } footer: {
                Text(
                    "Shortcuts are bound to physical keys, so they keep working when you switch keyboard layouts. Click a field and press the new combination."
                )
            }
            Section {
                Toggle("Enable push-to-talk", isOn: $settings.pushToTalkEnabled)
                HotkeyRecorder(title: "Hold to talk", hotkey: $settings.hotkeyPushToTalk)
                    .disabled(!settings.pushToTalkEnabled)
            } header: {
                Text("Push-to-talk")
            } footer: {
                Text(
                    "Hold the key while speaking; release it and the text is inserted. Taps shorter than 300 ms are ignored. Both modes work at the same time."
                )
            }
            if let error = model.hotkeyError {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            Section {
                Button("Reset to defaults") {
                    settings.hotkeyStart = .defaultStart
                    settings.hotkeyStop = .defaultStop
                    settings.hotkeyCancel = .defaultCancel
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.hotkeyStart) { model.registerHotkeys() }
        .onChange(of: settings.hotkeyStop) { model.registerHotkeys() }
        .onChange(of: settings.hotkeyCancel) { model.registerHotkeys() }
        .onChange(of: settings.hotkeyPushToTalk) { model.registerHotkeys() }
        .onChange(of: settings.pushToTalkEnabled) { model.registerHotkeys() }
    }
}

/// Click, then press a key combination. Uses a local NSEvent monitor while armed.
struct HotkeyRecorder: View {
    let title: String
    @Binding var hotkey: Hotkey
    @State private var armed = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(title) {
            Button {
                armed ? disarm() : arm()
            } label: {
                Text(armed ? "Press keys…" : hotkey.display)
                    .frame(minWidth: 110)
            }
            .buttonStyle(.bordered)
            .tint(armed ? .accentColor : nil)
        }
        .onDisappear { disarm() }
    }

    private func arm() {
        armed = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {  // Escape cancels
                disarm()
                return nil
            }
            var mods: UInt32 = 0
            if event.modifierFlags.contains(.command) { mods |= Hotkey.cmd }
            if event.modifierFlags.contains(.shift) { mods |= Hotkey.shift }
            if event.modifierFlags.contains(.option) { mods |= Hotkey.option }
            if event.modifierFlags.contains(.control) { mods |= Hotkey.control }
            guard mods != 0 else { return nil }  // require at least one modifier for a global hotkey
            hotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: mods)
            disarm()
            return nil
        }
    }

    private func disarm() {
        armed = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - Audio

struct AudioSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Input device") {
                Picker(
                    "Microphone",
                    selection: Binding(
                        get: { settings.deviceUID ?? "" },
                        set: { uid in model.selectDevice(model.inputDevices.first { $0.uid == uid }) }
                    )
                ) {
                    Text("System default").tag("")
                    ForEach(model.inputDevices) { Text($0.name).tag($0.uid) }
                }
                Button("Refresh") { model.refreshDevices() }
                Toggle("Prefer the built-in microphone over Bluetooth headsets", isOn: $settings.preferBuiltInMic)
                Text(
                    "Bluetooth headset microphones run at low quality and sometimes deliver no audio at all. With this on, Jarvis records from the Mac's own microphone whenever the system default is a Bluetooth device."
                )
                .font(.caption).foregroundStyle(.secondary)
                if model.silentInputDetected {
                    Label(
                        "The last recording delivered only silence. Check the device and Microphone permission.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            }
            Section {
                LabeledContent("Speech threshold") {
                    Slider(value: $settings.vadThreshold, in: 0.2...0.9, step: 0.05) { Text("") }
                    Text(String(format: "%.2f", settings.vadThreshold)).monospacedDigit().frame(width: 40)
                }
                Stepper(
                    "Minimum speech: \(settings.minSpeechMs) ms", value: $settings.minSpeechMs, in: 100...1000, step: 50
                )
                Stepper(
                    "Pause that ends a chunk: \(settings.minSilenceMs) ms", value: $settings.minSilenceMs,
                    in: 200...2000, step: 100)
            } header: {
                Text("Voice activity detection")
            } footer: {
                Text(
                    "Defaults (0.50 / 250 ms / 600 ms) match the previous Jarvis. A shorter pause gives faster partial results; a longer one merges sentences into one chunk, which can improve mixed-language accuracy."
                )
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.vadThreshold) { model.applyVADSettings() }
        .onChange(of: settings.minSpeechMs) { model.applyVADSettings() }
        .onChange(of: settings.minSilenceMs) { model.applyVADSettings() }
    }
}

// MARK: - Models

struct ModelSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(WhisperModel.catalog) { m in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(m.display).fontWeight(model.settings.modelKey == m.id ? .semibold : .regular)
                            Text("\(m.note)  ·  ~\(m.approxSizeMB) MB").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.settings.modelKey == m.id {
                            statusBadge
                        } else {
                            Button(ModelManager.isDownloaded(m) ? "Use" : "Download & use") { model.selectModel(m) }
                        }
                    }
                }
            } header: {
                Text("Speech model")
            } footer: {
                Text(
                    "Models are stored in ~/Library/Application Support/Jarvis/Models. The first load of a model prepares it for the Neural Engine and can take a couple of minutes; later launches take a few seconds."
                )
            }
            if model.models.lastLoadSeconds > 0 {
                Section("Last load") { Text(String(format: "%.1f s", model.models.lastLoadSeconds)) }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var statusBadge: some View {
        switch model.models.status {
        case .downloading(let p):
            ProgressView(value: p).frame(width: 100)
            Text("\(Int(p * 100)) %").monospacedDigit()
        case .loading:
            ProgressView().controlSize(.small)
            Text("Preparing…")
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let m):
            Label(m, systemImage: "xmark.octagon").foregroundStyle(.red).lineLimit(2)
            Button("Retry") { model.selectModel(model.settings.model) }
        case .idle:
            Button("Load") { model.selectModel(model.settings.model) }
        }
    }
}

// MARK: - Permissions

struct PermissionSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(model.permissions, id: \.0) { permission, state in
                    PermissionRow(permission: permission, state: state)
                }
            } footer: {
                Text(
                    "Microphone is needed to hear you. Accessibility lets Jarvis type into other apps and send ⌘V. Nothing else is requested; audio never leaves this Mac."
                )
            }
            Section {
                Button("Re-check") { model.refreshPermissions() }
            }
        }
        .formStyle(.grouped)
    }
}

struct PermissionRow: View {
    @Environment(AppModel.self) private var model
    let permission: Permission
    let state: PermissionState

    var body: some View {
        HStack {
            Image(systemName: state == .granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(state == .granted ? .green : .red)
            Text(permission.title)
            Spacer()
            if state != .granted {
                Button("Request") { model.requestPermission(permission) }
                Button("Open System Settings") { Permissions.openSettings(for: permission) }
            } else {
                Text("Granted").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - About

struct AboutSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            Text("SAP Jarvis").font(.title).bold()
            Text(
                "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))"
            )
            .foregroundStyle(.secondary)
            Text(
                "On-device dictation for macOS. Speak in Czech, English or a mix; the text appears where your cursor is. No audio or text ever leaves this Mac."
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)
            Image("SAPLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: 24)
                .accessibilityLabel("SAP")
                .padding(.top, 6)
            HStack(spacing: 12) {
                Button("Report an Issue…") { model.reportIssue() }
                Button("Welcome & Permissions…") { model.showOnboarding() }
            }
            .controlSize(.small)
            Divider().frame(width: 200)
            Grid(alignment: .leading, verticalSpacing: 4) {
                GridRow {
                    Text("Engine").foregroundStyle(.secondary)
                    Text(model.models.transcriber?.identifier ?? "not loaded")
                }
                GridRow {
                    Text("VAD").foregroundStyle(.secondary)
                    Text("Silero v6 (FluidAudio)")
                }
                GridRow {
                    Text("Last insert").foregroundStyle(.secondary)
                    Text(model.lastInsertion?.rawValue ?? "—")
                }
                if let s = model.lastLatencySeconds {
                    GridRow {
                        Text("Last stop → text").foregroundStyle(.secondary)
                        Text(String(format: "%.2f s", s))
                    }
                }
            }
            .font(.callout)
        }
        .padding(24)
    }
}
