import AppKit
import JarvisCore
import SwiftUI

/// First-run window: permissions, model download, and a quick "try it" guide. Hosted in an
/// `NSWindow` so it can be shown from the app delegate before any SwiftUI scene exists.
@MainActor
final class OnboardingWindowController {
    private let window: NSWindow

    init(model: AppModel) {
        let view = OnboardingView().environment(model)
        let hosting = NSHostingController(rootView: view)
        window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to SAP Jarvis"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 560))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                VStack(alignment: .leading) {
                    Text("SAP Jarvis").font(.title).bold()
                    Text("Speak. The text appears where your cursor is.").foregroundStyle(.secondary)
                }
                Spacer()
                Image("SAPLogo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 24)
                    .accessibilityLabel("SAP")
            }

            GroupBox("1. Permissions") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.permissions, id: \.0) { permission, state in
                        PermissionRow(permission: permission, state: state)
                    }
                    if model.needsRelaunchForPermissions {
                        HStack {
                            Label(
                                "Accessibility granted. Restart Jarvis so macOS applies it.",
                                systemImage: "arrow.clockwise")
                            Spacer()
                            Button("Restart Jarvis") { model.relaunch() }
                        }
                    } else {
                        Text(
                            "This list refreshes every few seconds. If Accessibility was granted while Jarvis was running, a restart may be needed; Jarvis will say so here."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }

            GroupBox("2. Speech model") {
                HStack {
                    VStack(alignment: .leading) {
                        Text(model.settings.model.display)
                        Text(model.models.status.label).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    modelProgress
                }
                .padding(4)
            }

            GroupBox("3. Try it") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Click into any text field.", systemImage: "cursorarrow.click")
                    Label(
                        "Press \(model.settings.hotkeyStart.display) and speak. Czech, English or both.",
                        systemImage: "mic")
                    Label(
                        "Press \(model.settings.hotkeyStop.display). The text is inserted at the cursor.",
                        systemImage: "text.insert")
                    Label("\(model.settings.hotkeyCancel.display) cancels at any time.", systemImage: "xmark.circle")
                    if model.settings.pushToTalkEnabled {
                        Label(
                            "Or hold \(model.settings.hotkeyPushToTalk.display) while you speak and release to insert.",
                            systemImage: "hand.tap")
                    }
                }
                .padding(4)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Button("Report an Issue…") { model.reportIssue() }
                Spacer()
                Button(ready ? "Done" : "Close") { model.finishOnboarding() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { model.refreshPermissions() }
    }

    private var ready: Bool { !model.permissionsMissing && model.models.status.isReady }

    @ViewBuilder private var modelProgress: some View {
        switch model.models.status {
        case .downloading(let p):
            ProgressView(value: p).frame(width: 120)
        case .loading:
            ProgressView().controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Button("Retry") { model.selectModel(model.settings.model) }
        case .idle:
            Button("Load") { model.selectModel(model.settings.model) }
        }
    }
}
