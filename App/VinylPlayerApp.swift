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

    /// One place on screen at a time: the desktop turntable, the notch, or neither.
    private func apply(_ mode: DisplayMode) {
        switch mode {
        case .desktop: notch.hide(); panel.show()
        case .notch: panel.hide(); notch.show()
        case .menuBar: panel.hide(); notch.hide()
        }
    }

    /// A friend sent records: the pet hops, and a notification opens the inbox.
    private func announce(_ shares: [Share]) {
        model.petTapped()
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
            LibraryWindowController.shared.show(.inbox, share: share)
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
        Divider()
        Button(social.unopenedCount > 0 ? "Library — \(social.unopenedCount) new record\(social.unopenedCount == 1 ? "" : "s")…" : "Library…") {
            LibraryWindowController.shared.show(social.unopenedCount > 0 ? .inbox : nil)
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
        Toggle("Pet Operates the Tonearm", isOn: $prefs.petOperatesArm)
        Toggle("Sound", isOn: $prefs.sound)
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
                Picker("Show as", selection: $prefs.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Text(prefs.displayMode.blurb).font(.caption).foregroundStyle(.secondary)
                Toggle("Open at login", isOn: Binding(get: { prefs.launchAtLogin }, set: { prefs.launchAtLogin = $0 }))
                if prefs.displayMode == .desktop {
                    Toggle("Float above other windows", isOn: $prefs.floatAboveWindows)
                }
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
            Section("Sharing links") {
                TextField("Your name", text: $prefs.senderName, prompt: Text("A friend"))
                TextField("Shared record page", text: $prefs.shareBaseURL)
                Text("For people without the app. Host the web folder (e.g. on Vercel) and paste its shared-record address here. Friends with the app can also get records straight to their inbox: open the Library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}
