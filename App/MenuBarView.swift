import JarvisCore
import SwiftUI

/// The status-bar menu. Plain `.menu` style: instant, keyboard-navigable, no custom popover.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        statusSection
        Divider()
        controlSection
        Divider()
        languageMenu
        modelMenu
        microphoneMenu
        Divider()
        Toggle(
            "Completion sound",
            isOn: Binding(get: { model.settings.completionSound }, set: { model.settings.completionSound = $0 }))
        insertionMenu
        Divider()
        if model.permissionsMissing {
            Button {
                model.showOnboarding()
            } label: {
                Label("Fix permissions…", systemImage: "exclamationmark.triangle")
            }
        }
        if model.needsRelaunchForPermissions {
            Button {
                model.relaunch()
            } label: {
                Label("Restart Jarvis to apply permissions", systemImage: "arrow.clockwise")
            }
        }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",", modifiers: .command)
        Button("Welcome & Permissions…") { model.showOnboarding() }
        Button("Report an Issue…") { model.reportIssue() }
        Divider()
        Button("Quit Jarvis") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    // MARK: - Sections

    @ViewBuilder private var statusSection: some View {
        Text(model.statusText)
        if model.state == .recording, !model.partialText.isEmpty, model.settings.showPreview {
            Text(preview(model.partialText)).font(.caption)
        }
        if model.state == .idle, !model.lastText.isEmpty {
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(model.lastText, forType: .string)
            } label: {
                Text("Copy last: “\(preview(model.lastText))”")
            }
        }
        if let error = model.lastError {
            Text("⚠︎ \(error)").font(.caption)
        }
        if let error = model.hotkeyError {
            Text("⚠︎ Hotkeys: \(error)").font(.caption)
        }
    }

    @ViewBuilder private var controlSection: some View {
        Button {
            model.start()
        } label: {
            Label("Start recording  \(model.settings.hotkeyStart.display)", systemImage: "record.circle")
        }
        .disabled(model.state != .idle || !model.models.status.isReady)

        Button {
            model.stop()
        } label: {
            Label("Stop and insert  \(model.settings.hotkeyStop.display)", systemImage: "stop.circle")
        }
        .disabled(model.state != .recording)

        Button {
            model.cancel()
        } label: {
            Label("Cancel  \(model.settings.hotkeyCancel.display)", systemImage: "xmark.circle")
        }
        .disabled(model.state == .idle)

        if model.settings.pushToTalkEnabled {
            Text("Hold \(model.settings.hotkeyPushToTalk.display) to talk")
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(Language.all) { lang in
                Button {
                    model.selectLanguage(lang.id)
                } label: {
                    if model.settings.language == lang.id {
                        Label("\(lang.flag) \(lang.name)", systemImage: "checkmark")
                    } else {
                        Text("\(lang.flag) \(lang.name)")
                    }
                }
            }
        } label: {
            Text(
                "Language: \(Language.byID(model.settings.language).flag) \(Language.byID(model.settings.language).name)"
            )
        }
    }

    private var modelMenu: some View {
        Menu {
            ForEach(WhisperModel.catalog) { m in
                Button {
                    model.selectModel(m)
                } label: {
                    let downloaded = ModelManager.isDownloaded(m) ? "" : "  (download ~\(m.approxSizeMB) MB)"
                    if model.settings.modelKey == m.id {
                        Label("\(m.display)\(downloaded)", systemImage: "checkmark")
                    } else {
                        Text("\(m.display)\(downloaded)")
                    }
                }
            }
            Divider()
            Text(model.models.status.label)
        } label: {
            Text("Model: \(model.settings.model.display)")
        }
    }

    private var microphoneMenu: some View {
        Menu {
            Button {
                model.selectDevice(nil)
            } label: {
                if model.settings.deviceUID == nil {
                    Label("System default", systemImage: "checkmark")
                } else {
                    Text("System default")
                }
            }
            Divider()
            ForEach(model.inputDevices) { device in
                Button {
                    model.selectDevice(device)
                } label: {
                    if model.settings.deviceUID == device.uid {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
            Divider()
            Button("Refresh devices") { model.refreshDevices() }
        } label: {
            Text("Microphone: \(model.settings.deviceName ?? "System default")")
        }
    }

    private var insertionMenu: some View {
        Menu {
            ForEach(InsertionMode.allCases) { mode in
                Button {
                    model.settings.insertionMode = mode
                } label: {
                    if model.settings.insertionMode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            Text("Output: \(model.settings.insertionMode.title)")
        }
    }

    private func preview(_ text: String, max: Int = 60) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > max ? String(flat.prefix(max)) + "…" : flat
    }
}
