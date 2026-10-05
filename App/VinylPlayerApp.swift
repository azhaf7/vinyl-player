import SwiftUI
import AppKit
import Combine

@main
struct VinylPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(app: delegate)
        } label: {
            Image(systemName: "record.circle")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(app: delegate)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let model = PlayerModel()
    private(set) lazy var panel = DesktopPanelController(model: model)
    private var bridge: WidgetBridge?
    private var levelObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        bridge = WidgetBridge(model: model)
        panel.show()
        levelObserver = Preferences.shared.$floatAboveWindows.sink { [weak self] _ in
            DispatchQueue.main.async { self?.panel.applyLevel() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return true
    }
}

private struct MenuContent: View {
    @ObservedObject var app: AppDelegate
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        let model = app.model
        Text(model.track.title + " — " + model.track.artist)
        Button(model.pendingPlaying ? "Pause" : "Play") { model.toggle() }
        Button("Next") { model.next() }
        Button("Previous") { model.previous() }
        Divider()
        Button(app.panel.isVisible ? "Hide Player" : "Show Player") { app.panel.toggle() }
        Button("Move Player to Top Right") { app.panel.show(); app.panel.resetPosition() }
        Toggle("Float Above Windows", isOn: $prefs.floatAboveWindows)
        Divider()
        Toggle("Pet Operates the Tonearm", isOn: $prefs.petOperatesArm)
        Toggle("Arm Follows the Groove", isOn: $prefs.armFollowsGroove)
        Toggle("Sound", isOn: $prefs.sound)
        Picker("Turntable", selection: $prefs.drive) {
            ForEach(DriveChoice.allCases) { Text($0.rawValue).tag($0) }
        }
        Picker("Appearance", selection: $prefs.theme) {
            ForEach(ThemeChoice.allCases) { Text($0.rawValue).tag($0) }
        }
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit Vinyl Player") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct SettingsView: View {
    @ObservedObject var app: AppDelegate
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Player") {
                Toggle("Open at login", isOn: Binding(get: { prefs.launchAtLogin }, set: { prefs.launchAtLogin = $0 }))
                Toggle("Float above other windows", isOn: $prefs.floatAboveWindows)
                Toggle("Pet operates the tonearm", isOn: $prefs.petOperatesArm)
                Toggle("Tonearm follows the groove", isOn: $prefs.armFollowsGroove)
                Toggle("Needle drop and crackle", isOn: $prefs.sound)
                Picker("Turntable", selection: $prefs.drive) {
                    ForEach(DriveChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Appearance", selection: $prefs.theme) {
                    ForEach(ThemeChoice.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Sharing") {
                TextField("Your name", text: $prefs.senderName, prompt: Text("A friend"))
                TextField("Shared record page", text: $prefs.shareBaseURL)
                Text("Links open the page in web/shared-record. Host that folder (GitHub Pages, Netlify…) and paste its address here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Music") {
                LabeledContent("Source", value: app.model.service.name)
                Text("Spotify sign-in is coming next. Until then the player uses six sample songs with their real covers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}
