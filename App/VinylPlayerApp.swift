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
    private(set) lazy var notch = NotchController(model: model)
    private var bridge: WidgetBridge?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = Preferences.shared
        FrameDriver.shared.onTick = { [weak self] dt in self?.model.tick(dt) }
        bridge = WidgetBridge(model: model)
        LibraryWindowController.shared.model = model

        prefs.$musicSource.removeDuplicates().sink { [weak self] source in
            DispatchQueue.main.async { self?.connect(source) }
        }.store(in: &bag)
        prefs.$displayMode.removeDuplicates().sink { [weak self] mode in
            DispatchQueue.main.async { self?.apply(mode) }
        }.store(in: &bag)
        prefs.$floatAboveWindows.sink { [weak self] _ in
            DispatchQueue.main.async { self?.panel.applyLevel() }
        }.store(in: &bag)
        prefs.$playerSize.removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.panel.applySize() }
        }.store(in: &bag)

        PlaylistPlayer.shared.model = model
        HotKeys.shared.onPress = { [weak self] id in
            guard let m = self?.model else { return }
            switch id {
            case 1: m.toggle()
            case 2: PlaylistPlayer.shared.playlist != nil && !m.isLive ? PlaylistPlayer.shared.skip() : m.next()
            case 3: m.previous()
            case 4: CollectionStore.shared.toggleLike(m.track)
            default: break
            }
        }
        prefs.$hotKeys.removeDuplicates().sink { on in DispatchQueue.main.async { HotKeys.shared.setEnabled(on) } }.store(in: &bag)
        if !prefs.didOnboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                WelcomeWindowController.shared.show(model: self.model)
            }
        }
    }

    private func connect(_ source: MusicSource) {
        switch source {
        case .nowPlaying: model.use(NowPlayingService())
        case .samples: model.use(MockPlaybackService())
        }
    }

    /// One place on screen at a time: the desktop turntable or the notch. The menu bar icon is always there.
    private func apply(_ mode: DisplayMode) {
        switch mode {
        case .desktop: notch.hide(); panel.show()
        case .notch: panel.hide(); notch.show()
        }
    }

    /// vinyl://record?song=…: someone shared a record with us.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "vinyl" {
            if let record = SharedRecord(url: url) {
                LinkInbox.shared.add(record)
                model.wave()
                SharedRecordWindowController.shared.show(record)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        LibraryWindowController.shared.show()
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
        Button(CollectionStore.shared.isLiked(model.track) ? "Unlike Song" : "Like Song") { CollectionStore.shared.toggleLike(model.track) }
        Divider()
        Button("Library…") { LibraryWindowController.shared.show() }
        .keyboardShortcut("l")
        Divider()
        Picker("Show As", selection: $prefs.displayMode) {
            ForEach(DisplayMode.allCases) { Text($0.rawValue).tag($0) }
        }
        if prefs.displayMode == .desktop {
            Picker("Size", selection: $prefs.playerSize) {
                ForEach(PlayerSize.allCases) { Text($0.rawValue).tag($0) }
            }
            Toggle("Float Above Windows", isOn: $prefs.floatAboveWindows)
            Button("Move Player to Top Right") { app.panel.show(); app.panel.resetPosition() }
        }
        Picker("Music", selection: $prefs.musicSource) {
            ForEach(MusicSource.allCases) { Text($0.rawValue).tag($0) }
        }
        Divider()
        Toggle("Show the Pet", isOn: $prefs.showPet)
        Toggle("Pet Operates the Tonearm", isOn: $prefs.petOperatesArm)
        Toggle("Sound", isOn: $prefs.sound)
        Picker("Appearance", selection: $prefs.theme) {
            ForEach(ThemeChoice.allCases) { Text($0.rawValue).tag($0) }
        }
        Divider()
        Button("Settings…") { LibraryWindowController.shared.show(.settings) }
            .keyboardShortcut(",")
        Button("Quit Vinyl Player") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct SettingsView: View {
    @ObservedObject var app: AppDelegate

    var body: some View {
        SettingsForm(model: app.model)
            .frame(width: 500, height: 640)
            .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}
