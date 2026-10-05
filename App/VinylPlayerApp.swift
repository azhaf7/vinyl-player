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
    private var sourceObserver: AnyCancellable?
    private var notchObserver: AnyCancellable?
    private(set) lazy var notch = NotchController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        FrameDriver.shared.onTick = { [weak self] dt in self?.model.tick(dt) }
        bridge = WidgetBridge(model: model)
        sourceObserver = Preferences.shared.$musicSource.removeDuplicates().sink { [weak self] source in
            DispatchQueue.main.async { self?.connect(source) }
        }
        panel.show()
        notchObserver = Preferences.shared.$notchMode.removeDuplicates().sink { [weak self] on in
            DispatchQueue.main.async { on ? self?.notch.show() : self?.notch.hide() }
        }
        levelObserver = Preferences.shared.$floatAboveWindows.sink { [weak self] _ in
            DispatchQueue.main.async { self?.panel.applyLevel() }
        }
    }

    private func connect(_ source: MusicSource) {
        switch source {
        case .nowPlaying: model.use(NowPlayingService())
        case .samples: model.use(MockPlaybackService())
        }
    }

    /// vinyl://record?song=…: someone shared a record with us.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "vinyl" {
            if let record = SharedRecord(url: url) { SharedRecordWindowController.shared.show(record) }
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
        Picker("Music", selection: $prefs.musicSource) {
            ForEach(MusicSource.allCases) { Text($0.rawValue).tag($0) }
        }
        Divider()
        Button(model.pendingPlaying ? "Pause" : "Play") { model.toggle() }
        Button("Next") { model.next() }
        Button("Previous") { model.previous() }
        Divider()
        Button(app.panel.isVisible ? "Hide Player" : "Show Player") { app.panel.toggle() }
        Button("Move Player to Top Right") { app.panel.show(); app.panel.resetPosition() }
        Toggle("Float Above Windows", isOn: $prefs.floatAboveWindows)
        Toggle("Show in the Notch", isOn: $prefs.notchMode)
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
                Toggle("Show in the notch (record and pet at the top of the screen)", isOn: $prefs.notchMode)
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
                Picker("Follow", selection: $prefs.musicSource) {
                    ForEach(MusicSource.allCases) { Text($0.rawValue).tag($0) }
                }
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    Text(app.model.service.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Shows what the Spotify or Music app on this Mac is playing, and controls it. The first time, macOS asks to let Vinyl Player control the app; choose OK.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}
