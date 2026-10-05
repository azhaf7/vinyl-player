import SwiftUI
import AppKit
import Combine
import UserNotifications

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

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, UNUserNotificationCenterDelegate {
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

        // Accounts and in-app sharing.
        let social = SocialService.shared
        social.onNewShares = { [weak self] shares in self?.announce(shares) }
        social.nowPlayingProvider = { [weak self] in
            guard let m = self?.model else { return (nil, false) }
            return (m.isLive && m.track.sourceID == nil ? nil : m.track, m.pendingPlaying)
        }
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
        social.$state.sink { state in
            if case .signedIn = state {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }.store(in: &bag)
        UNUserNotificationCenter.current().delegate = self
        social.start(petName: PetSpec.at(model.pet).name)

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

    /// A friend sent records: the pet hops, and a notification opens the inbox.
    private func announce(_ shares: [Share]) {
        model.wave()
        for s in shares.prefix(3) {
            let content = UNMutableNotificationContent()
            content.title = (s.sender.map { $0.name } ?? "A friend") + " sent you a record"
            content.body = s.message.flatMap { $0.isEmpty ? nil : "“\($0)”" } ?? "Open it to see the song."
            content.sound = .default
            content.userInfo = ["share": s.id.uuidString]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: s.id.uuidString, content: content, trigger: nil))
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["share"] as? String
        DispatchQueue.main.async {
            let share = SocialService.shared.inbox.first { $0.id.uuidString == id }
            LibraryWindowController.shared.show(.friends, share: share)
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// vinyl://record?song=…: someone shared a record with us.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "vinyl" {
            if let record = SharedRecord(url: url) {
                LinkInbox.shared.add(record)
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
    @ObservedObject var social = SocialService.shared

    var body: some View {
        let model = app.model
        Text(model.track.title + " — " + model.track.artist)
        Button(model.pendingPlaying ? "Pause" : "Play") { model.toggle() }
        Button("Next") { model.next() }
        Button("Previous") { model.previous() }
        Button(CollectionStore.shared.isLiked(model.track) ? "Unlike Song" : "Like Song") { CollectionStore.shared.toggleLike(model.track) }
        Divider()
        Button(social.unopenedCount > 0 ? "Library — \(social.unopenedCount) new record\(social.unopenedCount == 1 ? "" : "s")…" : "Library…") {
            LibraryWindowController.shared.show(social.unopenedCount > 0 ? .friends : nil, page: social.unopenedCount > 0 ? .inbox : nil)
        }
        .keyboardShortcut("l")
        Divider()
        Picker("Show As", selection: $prefs.displayMode) {
            ForEach(DisplayMode.allCases) { Text($0.rawValue).tag($0) }
        }
        if prefs.displayMode == .desktop {
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
